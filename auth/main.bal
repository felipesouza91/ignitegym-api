import ballerina/crypto;
import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/os;
import ballerina/sql;
import ballerina/time;
import ballerina/uuid;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/log;

configurable int port = ?;

configurable string token_issuer = ?;
configurable string token_audience = ?;

string db_host = os:getEnv("DATABASE_HOST");
string db_username = os:getEnv("DATABASE_USERNAME");
string db_password = os:getEnv("DATABASE_PASSWORD");
string db_name = os:getEnv("DATABASE_NAME");
final string cert_path = os:getEnv("CERT_PATH");

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
    string avatar?;
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
    string id?;
    string name?;
    string email?;
    string avatar?;
    string token;
    string refresh_token;
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

type RefreshTokenRequest record {
    string refresh_token;
};

type UserOK record {|
    *http:Ok;
    UserDTO body;
|};

type ValidRequest record {|
    *http:Ok;
    jwt:Payload body;
|};

type AuthInvalid record {|
    *http:Unauthorized;
    ErrorDetails body;
|};

type RefreshToken record {
    time:Utc expires_in;
    string refresh_token;
    string user_id;
    time:Utc created_at;
};

final string publicKey = "2823869431363516509006392718966225393686686492746057458250676423225088364271327327657813178602773210";

final postgresql:Client userClientDb = check new (db_host, db_username, db_password, db_name, 5432);

service /auth on new http:Listener(port) {

    isolated resource function post valid(@http:Header string authorization) returns ValidRequest|AuthInvalid|error? {

        string jwt = authorization.substring(7);

        [jwt:Header, jwt:Payload]|jwt:Error result = jwt:decode(jwt);

        if result is jwt:Error {
            AuthInvalid authRequestError = {
                body: {message: "Invalid Token", details: "Token is invalid", timeStamp: time:utcToString(time:utcNow())}
            };
            return authRequestError;
        }

        if result[1].exp is () {
            AuthInvalid authInvalidResponse = {
                body: {message: "Invalid Token", details: "Invalid token", timeStamp: time:utcToString(time:utcNow())}
            };
            return authInvalidResponse;
        } else {
            var opoch = result[1].exp ?: 0;
            time:Utc endDate = [opoch, 0.0];

            if time:utcDiffSeconds(endDate, time:utcNow()) <= <decimal>0 {
                AuthInvalid authInvalidResponse = {
                    body: {message: "Invalid Token", details: "Token expired", timeStamp: time:utcToString(time:utcNow())}
                };
                return authInvalidResponse;
            }
        }

        ValidRequest resultResponse = {
            body: result[1]
        };
        return resultResponse;
    }

    isolated resource function post token(UserValid data) returns AppTokenReponse|UserNotFound|AppBadRequestError|error {

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

        check result.close();

        string jwt = createToken(user.value.id.toString());

        RefreshToken new_refresh_token = generateRefreshToken(user.value.id);

        sql:ParameterizedQuery inserQuery = `INSERT INTO refresh_tokens(expires_in, refresh_token, user_id) VALUES(${time:utcToCivil(new_refresh_token.expires_in)} , ${new_refresh_token.refresh_token} , ${new_refresh_token.user_id}::uuid)`;

        var insertResult = userClientDb->execute(inserQuery);
        string refresh_token = "";
        if insertResult is sql:Error {
            io:println(insertResult);
            io:println("Erro ao inserir token");
            AppBadRequestError badRequest = {
                body: {message: "User Error", details: "Erro try late", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }
        refresh_token = new_refresh_token.refresh_token;

        AppTokenReponse response = {
            body: {id: user.value.id, name: user.value.name, email: user.value.email, token: jwt, refresh_token: refresh_token, avatar: user.value.avatar}
        };

        return response;
    };

    isolated resource function post create(InputUser input) returns AppUserCreated|AppBadRequestError|error? {

        stream<User, sql:Error?> userExitsResult = userClientDb->query(` SELECT * FROM USERS WHERE EMAIL = ${input.email} `);

        var userExists = check userExitsResult.next();

        if userExists != () {
            AppBadRequestError badRequest = {
                body: {message: "User validation", details: "Email/password invalid", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        check userExitsResult.close();

        byte[]|error output = crypto:hmacSha256(input.password.toBytes(), publicKey.toBytes());

        if output is error {
            io:print(output);
            io:println(output.message());
            AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        sql:ParameterizedQuery query = `INSERT INTO USERS(NAME, EMAIL, PASSWORD) VALUES(${input.name}, ${input.email}, ${output.toBase16()})`;
        sql:ExecutionResult|error result = userClientDb->execute(query);

        stream<User, sql:Error?> resultUser = userClientDb->query(`SELECT * FROM USERS WHERE EMAIL = ${input.email} `);

        var user = check resultUser.next();

        if user is () {
            io:println("User not found after create");
            AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }
        string id = user.value.id;

        check resultUser.close();

        RefreshToken new_refresh_token = generateRefreshToken(id);

        sql:ParameterizedQuery inserQuery = `INSERT INTO refresh_tokens(expires_in, refresh_token, user_id) VALUES(${time:utcToCivil(new_refresh_token.expires_in)} , ${new_refresh_token.refresh_token} , ${new_refresh_token.user_id}::uuid)`;

        var insertResult = userClientDb->execute(inserQuery);

        string refresh_token = "";

        if insertResult is sql:Error {
            io:print(insertResult.message());
            io:println("Erro ao inserir token");
            AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }
        refresh_token = new_refresh_token.refresh_token;

        if result is sql:ExecutionResult {
            string jwt = createToken(id.toString());
            AppUserCreated userCreated = {
                body: {
                    id: user.value.id,
                    email: user.value.email,
                    name: user.value.name,
                    avatar: user.value.avatar,
                    token: jwt,
                    refresh_token: refresh_token}
            };
            return userCreated;
        }
        AppBadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };

        check userClientDb.close();

        return badRequest;
    };

    isolated resource function post refresh\-token(RefreshTokenRequest data) returns AppTokenReponse|AppBadRequestError|error? {
        if data.refresh_token == "" {
            AppBadRequestError badRequest = {
                body: {message: "Refresh Token Error", details: "Refresh token is required", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }
        stream<RefreshToken, sql:Error?> refreshTokenResult = userClientDb->query(` SELECT * FROM refresh_tokens WHERE refresh_token = ${data.refresh_token} `);

        var refreshToken = check refreshTokenResult.next();

        if refreshToken is () {
            AppBadRequestError badRequest = {
                body: {message: "Refresh Token Error", details: "Refresh token not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }
        check refreshTokenResult.close();
        if time:utcDiffSeconds(refreshToken.value.expires_in, time:utcNow()) <= <decimal>0 {
            AppBadRequestError badRequest = {
                body: {message: "Refresh Token Error", details: "Refresh token expired", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        string jwt = createToken(refreshToken.value.user_id.toString());
        RefreshToken new_refresh_token = generateRefreshToken(refreshToken.value.user_id);

        sql:ParameterizedQuery inserQuery = `INSERT INTO refresh_tokens(expires_in, refresh_token, user_id) VALUES(${time:utcToCivil(new_refresh_token.expires_in)} , ${new_refresh_token.refresh_token} , ${new_refresh_token.user_id}::uuid)`;

        var insertResult = userClientDb->execute(inserQuery);

        if insertResult is sql:Error {
            io:println(insertResult.message());
            io:println("Erro ao inserir refresh token");
            AppBadRequestError badRequest = {
                body: {message: "Refresh Token Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        var resultDelete = userClientDb->execute(`DELETE FROM refresh_tokens WHERE refresh_token = ${new_refresh_token.refresh_token}`);

        if resultDelete is sql:Error {
            io:println(resultDelete.message());

            io:println("Erro ao remover token");
            AppBadRequestError badRequest = {
                body: {message: "Refresh Token Error", details: "Refresh token expired", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        AppTokenReponse response = {
            body: {token: jwt, refresh_token: new_refresh_token.refresh_token}
        };
        check userClientDb.close();

        return response;

    }
}

isolated function createToken(string userId) returns string {
    jwt:IssuerConfig issuerConfig = {
            username: userId,
            issuer: token_issuer,
            audience: token_audience,
            expTime: 50,

            signatureConfig: {
                algorithm: "RS256",
                config: {
                    keyFile: cert_path
                }
            }
        };

    string|jwt:Error jwt = jwt:issue(issuerConfig);
    if jwt is jwt:Error {
        log:printError(jwt.toString());
        io:print(jwt);
        return "";
    }

    return jwt;
}

isolated function generateRefreshToken(string user_id) returns RefreshToken {
    time:Utc expires_in = time:utcAddSeconds(time:utcNow(), 86400); // 7 days
    string refresh_token = uuid:createType4AsString();

    time:Utc created_at = time:utcNow();

    RefreshToken token = {
        expires_in: expires_in,
        refresh_token: refresh_token,
        user_id: user_id,
        created_at: created_at
    };

    return token;
}
