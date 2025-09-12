import ballerina/http;

import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;

type Exercise record {
    int id;
    string name;
    string series;
    int repetitions;
    @sql:Column { name: "group_name" }
    string group;
    string demo;
    string thumb;
    @sql:Column { name: "created_at" }
    time:Utc createdAt;

    @sql:Column { name: "updated_at" }
    time:Utc? updatedAt;
};

type ExerciseNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

type  ErrorDetails record {
    string message;
    string details;
    string timeStamp;
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
        string[] headers =   req.getHeaderNames();

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
        var userId = "1234";
        req.setHeader("x_user_id", userId);
      
        return ctx.next();
    }
}

postgresql:Client exercicesClientDb = check new(db_host,db_username,db_password, db_name , 5432);


service http:InterceptableService /exercises on new http:Listener(port) {



    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function get bygroups/[string group]() returns  Exercise[]|error? {
        stream<Exercise, sql:Error?>  result = exercicesClientDb->query(`SELECT * FROM exercises WHERE group_name = ${group} ORDER BY NAME`);

        Exercise[] exercises = [];

        check from Exercise exercise in result
        do {
            exercises.push(exercise);
        };

        return exercises;
    }

    resource function get [int id]() returns  Exercise|ExerciseNotFound|error? {
        stream<Exercise, sql:Error?>  result = exercicesClientDb->query(`SELECT * FROM exercises WHERE id = ${id}`);

        var exercise = check result.next();

        if exercise is (){
            ExerciseNotFound exerciseNotFound = {
                body: {message: " Exercise not found", details: " Exercise not found", timeStamp: time:utcToString(time:utcNow())}
            };
            return exerciseNotFound;
        }

        return exercise.value;
    }

} 