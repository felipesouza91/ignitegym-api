import ballerina/data.jsondata;
import ballerina/http;
import ballerina/io;
import ballerina/lang.value;
import ballerina/os;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

type Exercise record {
    string id;
    string name;
    string series;
    int repetitions;
    @sql:Column {name: "group_name"}
    string group;
    string demo;
    string thumb?;
    @sql:Column {name: "created_at"}
    time:Utc createdAt;
    @sql:Column {name: "updated_at"}
    time:Utc? updatedAt;
};

type ExerciseDTO record {
    string id;
    string name;
    string series;
    int repetitions;
    string group;
    string demo;
    string thumb?;
    string createdAt;
    string? updatedAt;
};

type ExerciseNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

type ErrorDetails record {
    string message;
    string details;
    string timeStamp;
};

configurable int port = ?;
string db_host = os:getEnv("DATABASE_HOST");
string db_username = os:getEnv("DATABASE_USERNAME");
string db_password = os:getEnv("DATABASE_PASSWORD");
string db_name = os:getEnv("DATABASE_NAME");
string auth_url = os:getEnv("AUTH_URL");

final http:Client authClient = check new (auth_url);

service class RequestInterceptor {
    *http:RequestInterceptor;

    isolated resource function 'default [string... path](
            http:RequestContext ctx, http:Request req)
        returns http:NotImplemented|http:Unauthorized|http:NextService|error? {
        string[] headers = req.getHeaderNames();

        var authorization = headers.filter(item => item.equalsIgnoreCaseAscii("authorization")).length();

        if authorization < 1 {
            return http:UNAUTHORIZED;
        }

        string authorizationData = check req.getHeader("authorization");

        http:Response|http:ClientError test = authClient->/auth/valid.post({}, {Authorization: authorizationData});
        if test is http:ClientError {
            io:println(test);
            return http:UNAUTHORIZED;
        }

        if test.statusCode != 200 {
            io:println(test);
            return http:UNAUTHORIZED;
        }

        json|http:ClientError data = test.getJsonPayload();
        if data is http:ClientError {
            io:println(data);

            return http:UNAUTHORIZED;
        }
        io:print(data);
        json|error userData = jsondata:read(data, `$`);
        if userData is error {
            io:println(userData);

            return http:UNAUTHORIZED;
        }

        string|error userId = value:ensureType(userData.sub, string);
        if userId is error {
            io:println(userId);

            return http:UNAUTHORIZED;
        }
        req.setHeader("x_user_id", userId);

        return ctx.next();
    }
}

final postgresql:Client exercicesClientDb = check new (
    db_host, db_username,
    db_password,
    db_name,
    5432,
    connectionPool = ({
        maxConnectionLifeTime: 18000 * 3,
        maxOpenConnections: 5,
        minIdleConnections: 2
        })
);

service http:InterceptableService /exercises on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    isolated resource function get bygroups/[string group_name]() returns ExerciseDTO[]|error? {
        io:println(group_name);
        stream<Exercise, sql:Error?> result = exercicesClientDb->query(`SELECT * FROM exercises WHERE group_name = ${group_name} ORDER BY NAME`);

        ExerciseDTO[] exercises = [];

        check from Exercise exercise in result
            do {
                string updateFormated = "";
                io:println(time:utcToString(exercise.createdAt));
                if exercise.updatedAt is () {
                    io:println("Updated at is null");
                } else {
                    var formtedAux = time:civilFromString(exercise.updatedAt.toString());
                    if formtedAux is time:Civil {
                        var updateFormatedtemp = time:civilToString(formtedAux);
                        if updateFormatedtemp is string {
                            updateFormated = updateFormatedtemp;
                        }
                    }
                }
                exercises.push({
                    id: exercise.id,
                    name: exercise.name,
                    series: exercise.series,
                    repetitions: exercise.repetitions,
                    group: exercise.group,
                    demo: exercise.demo,
                    thumb: exercise.thumb,
                    createdAt: time:utcToString(exercise.createdAt),
                    updatedAt: updateFormated
                });
            };
        check result.close();
        return exercises;
    }

    isolated resource function get [string id]() returns Exercise|ExerciseNotFound|error? {
        stream<Exercise, sql:Error?> result = exercicesClientDb->query(`SELECT * FROM exercises WHERE id = ${id}::uuid`);

        var exercise = check result.next();

        if exercise is () {
            ExerciseNotFound exerciseNotFound = {
                body: {message: " Exercise not found", details: " Exercise not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return exerciseNotFound;
        }
        check result.close();
        return exercise.value;
    }

}
