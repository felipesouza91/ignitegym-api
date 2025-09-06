import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;
import ballerina/crypto;

type User record {
    readonly int id;
    string name;
    string email;
    string password;
};

type UserDTO record {
    readonly int id;
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


type UserValid record{
    string email;
    string password;
};

type  ErrorDetails record {
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

table <User> key(id) users = table[];

postgresql:Client userClientDb = check new("localhost","user_service","user_service_password", "ignitegym", 5432);

# A service representing a network-accessible API
# bound to port `9090`.
service /users on new http:Listener(9090) {


    resource function post valid(UserValid data) returns UserOK|UserNotFound|BadRequestError|error  {
        io:println("initial data", data);

       
        byte[]|error output =  crypto:hmacSha256(data.password.toBytes(), publicKey.toBytes());
        
        if output is error {

            BadRequestError badRequest = {
                body: {message: "User not found", details: "User not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        stream<User, sql:Error?>  result =  userClientDb->query(`SELECT * FROM USERS WHERE EMAIL = ${data.email} AND PASSWORD = ${output.toBase16()}`);

        var user = check result.next();
    
        if user is () {
            UserNotFound userNotFound = {
                body: {message: "User not found", details: "User not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return userNotFound;
        }       
        
        return {
           body: {
                id: user.value.id,
                name: user.value.name,
                email: user.value.email
            }
        };
    };

    resource function post .(InputUser input) returns http:Created|BadRequestError|error {

        stream<User, sql:Error?>  userExitsResult =  userClientDb->query(`SELECT * FROM USERS WHERE EMAIL = ${input.email}`);

        var userExists = check userExitsResult.next();

        if userExists != ()  {
            BadRequestError badRequest = {
                body: {message: "User validation", details: "Email already exits.", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }  
        
        byte[]|error output =  crypto:hmacSha256(input.password.toBytes(), publicKey.toBytes());
        
        if output is error {
            io:println(output.message());
            BadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        sql:ParameterizedQuery query = `INSERT INTO USERS(NAME, EMAIL, PASSWORD) VALUES(${input.name}, ${input.email}, ${output.toBase16()})`;
        sql:ExecutionResult|error result =   userClientDb->execute(query);

        if result is sql:ExecutionResult {
            return http:CREATED;
        }
        BadRequestError badRequest = {
                body: {message: "Create User Error", details: "Error during create user", timeStamp: time:utcToString(time:utcNow())}
            };
        return badRequest;
    };

    resource function put .(UpdateUser data) returns UserOK|UserNotFound|BadRequestError|error{


        if data.name.length() < 1 || data.oldPassword.length() < 1  || data.newPassword.length() < 1  {
             BadRequestError badRequest = {
                body: {message: "Validation Error", details: "Fields name, oldPassword and newPassword are required", timeStamp: time:utcToString(time:utcNow())}
            };
            return badRequest;
        }

        int user_id = 1;

        byte[] oldPasswordEncode = check  crypto:hmacSha256(data.oldPassword.toBytes(), publicKey.toBytes());

        stream<User, sql:Error?>  userOldPasssowrdresult =  userClientDb->query(`SELECT * FROM USERS WHERE id = ${user_id}`);

        var user = check userOldPasssowrdresult.next();
    
        if user is ()  {
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

        byte[] newPasswordEncoded = check  crypto:hmacSha256(data.newPassword.toBytes(), publicKey.toBytes());


        sql:ParameterizedQuery query = `UPDATE USERS SET NAME = ${data.name}, PASSWORD = ${newPasswordEncoded.toBase16()} WHERE ID = ${user_id}`;
        sql:ExecutionResult|error result =   userClientDb->execute(query);

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