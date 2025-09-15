import ballerina/crypto;
import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/os;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable int port = ?;

configurable string token_issuer = ?;
configurable string token_audience = ?;

string db_host = os:getEnv("DATABASE_HOST");
string db_username = os:getEnv("DATABASE_USERNAME");
string db_password = os:getEnv("DATABASE_PASSWORD");
string db_name = os:getEnv("DATABASE_NAME");
string cert_path = os:getEnv("CERT_PATH");

type InputUser record {
    string name;
    string email;
    string password;
};

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

type TokenData record {|
    string jwt;
|};

type AppTokenReponse record {|
    *http:Ok;
    TokenData body;
|};

type AppUserCreated record {|
    *http:Created;
    TokenData body;
|};

type AppBadRequestError record {|
    *http:BadRequest;
    ErrorDetails body;
|};

type UserOK record {|
    *http:Ok;
    UserDTO body;
|};

type ValidRequest record {|
    *http:Ok;
    jwt:Payload body;
|};

string publicKey = "2823869431363516509006392718966225393686686492746057458250676423225088364271327327657813178602773210";

postgresql:Client userClientDb = check new (db_host, db_username, db_password, db_name, 5432);

service /auth on new http:Listener(port) {

    resource function post valid(@http:Header string authorization) returns ValidRequest|error? {

        string jwt = authorization.substring(7);

        [jwt:Header, jwt:Payload]|jwt:Error result = jwt:decode(jwt);

        if result is jwt:Error {
            io:println(result.message());
            return result;
        }

        ValidRequest resultResponse = {
            body: result[1]
        };
        return resultResponse;
    }

    resource function post token(UserValid data) returns AppTokenReponse|UserNotFound|AppBadRequestError|error {

        byte[]|error output = crypto:hmacSha256(data.password.toBytes(), publicKey.toBytes());

        if output is error {

            AppBadRequestError badRequest = {
                body: {message: "User not found", details: "User not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        stream<User, sql:Error?> result = userClientDb->query(`SELECT * FROM USERS WHERE EMAIL = ${data.email} AND PASSWORD = ${output.toBase16()}`);

        var user = check result.next();

        if user is () {
            UserNotFound userNotFound = {
                body: {message: "User not found", details: "User not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return userNotFound;
        }

        string jwt = createToken(user.value.id);

        AppTokenReponse response = {
            body: {jwt: jwt}
        };

        return response;
    };

    resource function post create(InputUser input) returns AppUserCreated|AppBadRequestError|error? {

        stream<User, sql:Error?> userExitsResult = userClientDb->query(` SELECT * FROM USERS WHERE EMAIL = ${input.email} `);

        var userExists = check userExitsResult.next();

        if userExists != () {
            AppBadRequestError badRequest = {
                body: {message: "User validation", details: "Email already exits.", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        byte[]|error output = crypto:hmacSha256(input.password.toBytes(), publicKey.toBytes());

        if output is error {
            io:println(output.message());
            AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        sql:ParameterizedQuery query = ` INSERT INTO USERS(NAME, EMAIL, PASSWORD) VALUES(${input.name}, ${input.email}, ${output.toBase16()})`;
        sql:ExecutionResult|error result = userClientDb->execute(query);

        stream<User, sql:Error?> resultUser = userClientDb->query(`SELECT * FROM USERS WHERE EMAIL = ${input.email} `);

        var user = check resultUser.next();

        if user is () {
            io:println("User not found after create");
        }
        string id = user is record {|User value;|} ? user.value.id : "";
        if result is sql:ExecutionResult {
            string jwt = createToken(id);
            AppUserCreated userCreated = {
                body: {jwt: jwt}
            };
            return userCreated;
        }
        AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
        return badRequest;
    };

}

function createToken(string userId) returns string {
    jwt:IssuerConfig issuerConfig = {
        username: userId,
        issuer: token_issuer,
        audience: token_audience,
        expTime: 3600,

        signatureConfig: {
            algorithm: "RS256",
            config: {
                keyFile: cert_path
            }
        }
    };

    string|jwt:Error jwt = jwt:issue(issuerConfig);
    if jwt is jwt:Error {
        io:print(jwt);
        return "";
    }

    return jwt;
}
