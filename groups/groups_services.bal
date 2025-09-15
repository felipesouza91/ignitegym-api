import ballerina/data.jsondata;
import ballerina/http;
import ballerina/io;
import ballerina/lang.value;
import ballerina/os;
import ballerina/sql;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

type Group record {
    @sql:Column {name: "group_name"}
    string group;
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

configurable int port = ?;
configurable string db_host = os:getEnv("DATABASE_HOST");
configurable string db_username = os:getEnv("DATABASE_USERNAME");
configurable string db_password = os:getEnv("DATABASE_PASSWORD");
configurable string db_name = os:getEnv("DATABASE_NAME");
configurable string auth_url = os:getEnv("AUTH_URL");

http:Client authClient = check new (auth_url);

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

postgresql:Client exercicesClientDb = check new (db_host, db_username, db_password, db_name, 5432);

service http:InterceptableService /groups on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function get .() returns Group[]|error? {
        stream<Group, sql:Error?> result = exercicesClientDb->query(`SELECT group_name FROM exercises GROUP BY group_name order by group_name`);

        Group[] groups = [];

        check from Group group in result
            do {
                groups.push(group);
            };

        return groups;
    }

}
