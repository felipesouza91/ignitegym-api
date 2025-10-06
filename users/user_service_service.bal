import ballerina/crypto;
import ballerina/data.jsondata;
import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/lang.value;
import ballerina/log;
import ballerina/os;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable int port = ?;
string db_host = os:getEnv("DATABASE_HOST");
string db_username = os:getEnv("DATABASE_USERNAME");
string db_password = os:getEnv("DATABASE_PASSWORD");
string db_name = os:getEnv("DATABASE_NAME");
string auth_url = os:getEnv("AUTH_URL");

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

type UpdateUser record {|
    string name?;
    string oldPassword?;
    string newPassword?;
|};

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

type ImageNotFound record {|
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

http:Client authClient = check new (auth_url);

service class RequestInterceptor {
    *http:RequestInterceptor;

    resource function 'default [string... path](
            http:RequestContext ctx, http:Request req)
        returns http:NotImplemented|http:Unauthorized|http:NextService|error? {

        if (req.rawPath.includes("/users/image") && req.method == "GET") {
            return ctx.next();
        }

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

service http:InterceptableService /users on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function put .(@http:Header string x_user_id, UpdateUser data) returns UserOK|UserNotFound|BadRequestError|error {
        io:println(data.toJsonString());
        string name = data.name ?: "";
        string oldPassword = data.oldPassword ?: "";
        string newPass = data.newPassword ?: "";
        string sqlPasswordData = "";

        stream<User, sql:Error?> userOldPasssowrdresult = userClientDb->query(`SELECT * FROM USERS WHERE id = ${x_user_id}::uuid`);

        var user = check userOldPasssowrdresult.next();

        if user is () {
            UserNotFound userNotFound = {
                    body: {message: "Validation Error", details: "Username/password invalid", timeStamp: time:utcToString(time:utcNow())}
                };
            return userNotFound;
        }
        check userOldPasssowrdresult.close();

        if oldPassword != "" && (newPass == "" || newPass.length() < 7) {
            BadRequestError badRequest = {
                body: {message: "Validation Error", details: "New password is required", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        if newPass != "" {
            if newPass.length() < 7 {
                BadRequestError badRequest = {
                    body: {message: "Validation Error", details: "New password length must be at least 7 characters", timeStamp: time:utcToString(time:utcNow())}
                };
                return badRequest;
            }
            if oldPassword == "" {
                BadRequestError badRequest = {
                        body: {message: "Validation Error", details: "Old password is required", timeStamp: time:utcToString(time:utcNow())}
                    };
                return badRequest;
            }

            byte[] oldPasswordEncode = check crypto:hmacSha256(oldPassword.toString().toBytes(), publicKey.toBytes());

            if user.value.password != oldPasswordEncode.toBase16() {
                BadRequestError badRequest = {
                    body: {message: "Validation Error", details: "Username/password invalid", timeStamp: time:utcToString(time:utcNow())}
                };
                return badRequest;
            }

        }

        name = name != user.value.name ? name : user.value.name;

        if newPass != "" {
            byte[] newPasswordEncoded = check crypto:hmacSha256(newPass.toString().toBytes(), publicKey.toBytes());
            sqlPasswordData = newPasswordEncoded.toBase16();
        } else {
            sqlPasswordData = user.value.password;
        }

        sql:ParameterizedQuery query = `UPDATE USERS SET NAME = ${name}, PASSWORD = ${sqlPasswordData} WHERE ID = ${x_user_id}::uuid`;
        sql:ExecutionResult|error result = userClientDb->execute(query);

        if result is sql:ExecutionResult {
            UserOK userOk = {
                body: {id: user.value.id, name: name, email: user.value.email}
            };
            return userOk;
        }
        io:println(result.message());
        BadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
        return badRequest;
    }

    resource function post avatar(@http:Header string x_user_id, http:Request request) returns http:Ok|BadRequestError|error? {
        stream<byte[], io:Error?> streamer = check request.getByteStream();
        string avatar_name = x_user_id + ".png";
        check io:fileWriteBlocksFromStream("./files/" + avatar_name, streamer);
        check streamer.close();

        sql:ParameterizedQuery query = `UPDATE USERS SET avatar = ${avatar_name} WHERE ID = ${x_user_id}::uuid`;
        sql:ExecutionResult|error result = userClientDb->execute(query);

        if result is error {
            log:printError("Erro ao realizar o update", result);
            check file:remove("./files/" + avatar_name);
            BadRequestError badResponse = {
                body: {message: "File error", details: "Erro when update avatar.", timeStamp: ""}
            };
            return badResponse;
        }

        return http:OK;
    }

    resource function get image/[string file_name](http:Caller caller) returns error? {
        byte[] fileBytes = check io:fileReadBytes("./files/" + file_name);

        http:Response response = new;

        response.setPayload(fileBytes);

        response.setHeader("Content-Type", "image/png");

        check caller->respond(response);
    }
};

