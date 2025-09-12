import ballerina/http;

import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;

type Group record {
    @sql:Column { name: "group_name" }
    string group;
};

type GroupNotFound record {|
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


service http:InterceptableService /groups on new http:Listener(port) {

    public function createInterceptors() returns [RequestInterceptor] {
        return [new RequestInterceptor()];
    }

    resource function get .() returns  Group[]|error? {
        stream<Group, sql:Error?>  result = exercicesClientDb->query(`SELECT group_name FROM exercises GROUP BY group_name order by group_name`);


        Group[] groups = [];

        check from Group group in result
        do {
            groups.push(group);
        };

        return groups;
    }

} 