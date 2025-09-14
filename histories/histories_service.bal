import ballerina/http;
import ballerina/io;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

type InputHistoryDTO record {
    int exerciseId;
};

type HistoryDTO record {
    int id;
    @sql:Column {name: "user_id"}
    int userId;
    @sql:Column {name: "exercise_id"}
    int exerciseId;
    string name;
    @sql:Column {name: "group_name"}
    string group;
    @sql:Column {name: "created_at"}
    time:Utc createdAt;
};

type HisotryByDateDTO record {
    string title;
    HistoryDTO[] exercises;
};

type GroupNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

type ErrorDetails record {
    string message;
    string details;
    string timeStamp;
};

type ServerError record {|
    *http:InternalServerError;
    ErrorDetails body;
|};

type AppBadRequest record {|
    *http:BadRequest;
    ErrorDetails body;
|};

type Exercise record {
    int id;
};

configurable int port = ?;
configurable string db_host = ?;
configurable string db_username = ?;
configurable string db_password = ?;
configurable string db_name = ?;

http:Client authClient = check new ("http://localhost:8090");

service class RequestInterceptor {
    *http:RequestInterceptor;

    resource function 'default [string... path](
            http:RequestContext ctx, http:Request req)
        returns http:NotImplemented|http:Unauthorized|http:NextService|error? {
        string[] headers = req.getHeaderNames();

        var authorization = headers.filter(item => item.equalsIgnoreCaseAscii("authorization")).length();

        if authorization < 1 {
            return http:UNAUTHORIZED;
        }

        string authorizationData = check req.getHeader("authorization");

        // http:Response|http:ClientError test =  authClient->/api/collections/users/auth\-refresh.post({}, {Authorization: authorizationData});

        // if test is http:ClientError {
        //     return http:UNAUTHORIZED;
        // }

        // if test.statusCode != 200 {
        //     return http:UNAUTHORIZED;
        // }

        // json|http:ClientError data =  test.getJsonPayload();
        // if data is http:ClientError {
        //     return http:UNAUTHORIZED;
        // }
        // json|error userData =  jsondata:read(data, `$.record`);
        // if userData is error {
        //     return http:UNAUTHORIZED;
        // }

        // string|error userId =  value:ensureType(userData.id, string);
        // if userId is error {
        //     return http:UNAUTHORIZED;
        // }
        var userId = "1";
        req.setHeader("x_user_id", userId);

        return ctx.next();
    }
}

postgresql:Client exercicesClientDb = check new (db_host, db_username, db_password, db_name, 5432);

service http:InterceptableService /histories on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function get .(@http:Header int x_user_id) returns HisotryByDateDTO[]|error? {

        sql:ParameterizedQuery exercisesHistory = `SELECT EH.id, EH.user_id, EH.exercise_id , E.name , E.group_name, EH.created_at FROM exercises_histories EH JOIN exercises E ON EH.exercise_id = E.id  WHERE EH.user_id = ${x_user_id}`;

        stream<HistoryDTO, sql:Error?> result = exercicesClientDb->query(exercisesHistory);

        string[] dates = [];

        HistoryDTO[] histories = [];

        check from HistoryDTO group in result
            do {
                histories.push(group);
            };

        histories.forEach(function(HistoryDTO data) {
            addDate(formatDate(data.createdAt), dates);
        });
        HisotryByDateDTO[] resultFormated = [];
        histories.forEach(function(HistoryDTO data) {
            string formatedDate = formatDate(data.createdAt);
            if resultFormated.length() < 1 {
                HisotryByDateDTO historie = {title: formatedDate, exercises: [data]};
                resultFormated.push(historie);
            } else {
                resultFormated.forEach(function(HisotryByDateDTO value) {
                    if (value.title == formatedDate) {
                        value.exercises.push(data);
                    } else {
                        HisotryByDateDTO historie = {title: formatedDate, exercises: [data]};
                        resultFormated.push(historie);
                    }
                });
            }

        });
        return resultFormated;
    }

    resource function post .(@http:Header int x_user_id, InputHistoryDTO input) returns http:Created|AppBadRequest|ServerError? {

        stream<Exercise, sql:Error?> exercisesQueryResult = exercicesClientDb->query(`SELECT id FROM exercises WHERE id = ${input.exerciseId}`);

        var exerciseResultData = exercisesQueryResult.next();
        if exerciseResultData is sql:Error {
            io:println("Exercice error");
            io:println(exerciseResultData);
            ServerError serverError = {
                body: {message: "Internal server error", details: "Error during process, try again later", timeStamp: time:utcToString(time:utcNow())}
            };
            return serverError;
        }

        if exerciseResultData is () {
            AppBadRequest appBadRequest = {
                body: {message: "Bad request", details: "Exercise not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return appBadRequest;
        }

        sql:ParameterizedQuery createHistory = `INSERT INTO exercises_histories(user_id, exercise_id) VALUES (${x_user_id}, ${input.exerciseId})`;
        var result = exercicesClientDb->execute(createHistory);

        if result is error {
            io:println(result);

            ServerError serverError = {
                body: {message: "Internal server error", details: "Erro during process try again later", timeStamp: time:utcToString(time:utcNow())}
            };
            return serverError;
        }
        return http:CREATED;
    }
}

function formatDate(time:Utc data) returns string {
    int day = time:utcToCivil(data).day;
    int month = time:utcToCivil(data).month;
    int year = time:utcToCivil(data).year;

    return string `${day}.${month}.${year}`;
}

function addDate(string date, string[] dates) {
    foreach var item in dates {
        if (item == date) {
            return;
        }
    }
    dates.push(date);
}
