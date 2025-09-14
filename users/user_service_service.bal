import ballerina/crypto;
import ballerina/data.jsondata;
import ballerina/http;
import ballerina/io;
import ballerina/lang.value;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable int port = ?;
configurable string db_host = ?;
configurable string db_username = ?;
configurable string db_password = ?;
configurable string db_name = ?;

type User record {
    readonly string id;
    string name;
    string email;
    string password;
};

type UserDTO record {
    readonly string id;
    string name;
    string email;
};

type InputUser record {
    string name;
    string email;
    string password;
};

type UpdateUser record {
    string name;
    string oldPassword;
    string newPassword;
};

type UserValid record {
    string email;
    string password;
};

type ErrorDetails record {
    string message;
    string details;
    string timeStamp;
};

type UserNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

type BadRequestError record {|
    *http:BadRequest;
    ErrorDetails body;
|};

type UserOK record {|
    *http:Ok;
    UserDTO body;
|};

string publicKey = "2823869431363516509006392718966225393686686492746057458250676423225088364271327327657813178602773210";

table<User> key(id) users = table [];

postgresql:Client userClientDb = check new (db_host, db_username, db_password, db_name, 5432);

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

        http:Response|http:ClientError test = authClient->/api/collections/users/auth\-refresh.post({}, {Authorization: authorizationData});

        if test is http:ClientError {
            return http:UNAUTHORIZED;
        }

        if test.statusCode != 200 {
            return http:UNAUTHORIZED;
        }

        json|http:ClientError data = test.getJsonPayload();
        if data is http:ClientError {
            return http:UNAUTHORIZED;
        }
        json|error userData = jsondata:read(data, `$.record`);
        if userData is error {
            return http:UNAUTHORIZED;
        }

        string|error userId = value:ensureType(userData.id, string);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        req.setHeader("x_user_id", userId);

        return ctx.next();
    }
}

service http:InterceptableService /users on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function put .(UpdateUser data) returns UserOK|UserNotFound|BadRequestError|error {

        if data.name.length() < 1 || data.oldPassword.length() < 1 || data.newPassword.length() < 1 {
            BadRequestError badRequest = {
                body: {message: "Validation Error", details: "Fields name, oldPassword and newPassword are required", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        int user_id = 1;

        byte[] oldPasswordEncode = check crypto:hmacSha256(data.oldPassword.toBytes(), publicKey.toBytes());

        stream<User, sql:Error?> userOldPasssowrdresult = userClientDb->query(`SELECT * FROM USERS WHERE id = ${user_id}`);

        var user = check userOldPasssowrdresult.next();

        if user is () {
            UserNotFound userNotFound = {
                body: {message: "Validation Error", details: "Username/password invalid", timeStamp: time:utcToString(time:utcNow())}
            };
            return userNotFound;
        }
        io:println(user.value.password);
        io:println(oldPasswordEncode.toBase16());
        io:println(user.value.password == oldPasswordEncode.toBase16());
        if user.value.password != oldPasswordEncode.toBase16() {
            BadRequestError badRequest = {
                body: {message: "Validation Error", details: "Username/password invalid", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        byte[] newPasswordEncoded = check crypto:hmacSha256(data.newPassword.toBytes(), publicKey.toBytes());

        sql:ParameterizedQuery query = `UPDATE USERS SET NAME = ${data.name}, PASSWORD = ${newPasswordEncoded.toBase16()} WHERE ID = ${user_id}`;
        sql:ExecutionResult|error result = userClientDb->execute(query);

        if result is sql:ExecutionResult {
            return {
                body: {id: user.value.id, name: data.name, email: user.value.email}
            };
        }
        io:println(result.message());
        BadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
        return badRequest;
    }

};

