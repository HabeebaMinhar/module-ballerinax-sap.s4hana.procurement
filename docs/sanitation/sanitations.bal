// Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
import ballerina/io;
import ballerina/lang.regexp;

type Items record {
    string 'type?;
    string[] 'enum?;
    string \$ref?;
};

type Schema record {
    string 'type?;
    boolean uniqueItems?;
    Items items?;
    string title?;
    json properties?;
};

type ParametersItem record {
    string name?;
    string 'in?;
    string description?;
    boolean explode?;
    Schema schema?;
    string \$ref?;
};

type EnumItems record {
    string 'type;
    string[] 'enum;
};

type EnumSchema record {
    string 'type;
    boolean uniqueItems;
    EnumItems items;
};

type EnumParametersItem record {
    string name;
    string 'in;
    string description;
    Schema schema;
    boolean explode;
};

type Get record {
    string summary?;
    string description?;
    string[] tags?;
    ParametersItem[] parameters;
    map<ResponseCode> responses?;
};

type Post record {
    string summary?;
    string description?;
    string[] tags?;
    ParametersItem[] parameters?;
    map<ResponseCode> responses?;
};

type Path record {
    json[] parameters?;
    Get get?;
    Post post?;
};

type Components record {
    map<json> schemas;
    map<ParametersItem> parameters;
    json responses;
    json securitySchemes;
};

type ResponseCode record {
    string description?;
    map<ResponseHeader> content?;
};

type ResponseHeader record {
    ResponseSchema schema?;
};

type ResponseSchema record {
    string title?;
    string schemaType?;
    map<ResponseProperties> properties?;
};

type ResponseProperties record {
    string title?;
    string objectType?;
    json properties?;
};

type Specification record {
    string openapi;
    json info;
    json externalDocs;
    string x\-sap\-api\-type;
    string x\-sap\-shortText;
    string x\-sap\-software\-min\-version;
    json[] x\-sap\-ext\-overview;
    json[] servers;
    json x\-sap\-extensible;
    json[] tags;
    map<Path> paths;
    Components components;
    json[] security;
};

public function main(string apiName) returns error? {
    string specPath = string `spec/${apiName}.json`;
    check sanitizeSchemaNames(apiName, specPath);
    check sanitizeEnumParamters(specPath);
    check sanitizResponseSchemaNames(specPath);
}

function sanitizeEnumParamters(string specPath) returns error? {
    json openAPISpec = check io:fileReadJson(specPath);

    Specification spec = check openAPISpec.cloneWithType(Specification);

    boolean isODATA4 = false;
    if (spec.x\-sap\-api\-type=="ODATAV4"){
        isODATA4 = true;
    }

    map<ParametersItem> selectedParameters = {};
    map<EnumSchema> selectedSchemas = {};

    map<Path> paths = spec.paths;
    foreach var [key, value] in paths.entries() {
        Get? getPath = value.get;
        if getPath is () {
            continue;
        }
        ParametersItem[] parameters = getPath.parameters;
        foreach int i in 0 ... parameters.length() - 1 {
            ParametersItem param = parameters[i];
            Schema? paramSchema = param.schema;
            if paramSchema is () {
                continue;
            }
            if paramSchema.'type != "array" {
                continue;
            }
            Items? items = paramSchema.items;
            if items is () {
                continue;
            }
            if items.'enum is () {
                continue;
            }
            string sanitizedParamName = getSanitizedParameterName(key, param.name ?: "",isODATA4);

            selectedSchemas[sanitizedParamName] = check param.schema.cloneWithType(EnumSchema);
            selectedParameters[sanitizedParamName] = {
                name: param.name,
                'in: param.'in,
                description: param.description,
                explode: param.explode,
                schema: {
                    "$ref": "#/components/schemas/" + sanitizedParamName
                }
            };
            parameters[i] = {
                \$ref: "#/components/parameters/" + sanitizedParamName
            };
        }
    }

    foreach var [schemaName, value] in selectedSchemas.entries() {
        spec.components.schemas[schemaName] = value.toJson();
    }

    foreach var [paramName, value] in selectedParameters.entries() {
        spec.components.parameters[paramName] = value;
    }

    check io:fileWriteJson(specPath, spec.toJson());

}

function getSanitizedParameterName(string key, string paramName,boolean isODATA4) returns string {

    string parameterName = "";

    regexp:RegExp pathRegex;
    if isODATA4 {
        pathRegex = re `^/([^/]+)?(/[^{]+)?(/[^/{]+)?(/.*)?$`;
    }else {
        pathRegex = re `/([^(]*)(\(.*\))?(/.*)?`;
    }

    regexp:Groups? groups = pathRegex.findGroups(key);
    if groups is () {
        // Can be requestApproval/ batch query path
        return "";
    }

    match (groups.length()) {
        0|1 => {
            io:println("Error: Invalid path" + key);
            parameterName += key;
        }
        2 => {
            regexp:Span? basePath = groups[1];
            if basePath !is () {
                parameterName += basePath.substring();
            }
        }
        3 => {
            regexp:Span? basePath = groups[1];
            if basePath !is () {
                parameterName += basePath.substring().concat("ByKey");
            }
        }
        4 => {
            regexp:Span? resourcePath = groups[3];
            if resourcePath !is () {
                string resourcePathString = resourcePath.substring();
                if resourcePathString.startsWith("/") {
                    resourcePathString = resourcePathString.substring(1);
                }
                if resourcePathString.startsWith("to_") {
                    resourcePathString = resourcePathString.substring(3);
                }
                resourcePathString = resourcePathString.substring(0, 1).toUpperAscii() + resourcePathString.substring(1);

                regexp:Span? basePath = groups[1];
                if basePath is () {
                    return "";
                }
                parameterName += resourcePathString.concat("Of", basePath.substring());
            }
        }
    }

    match (paramName) {
        "$filter" => {
            parameterName += "FilterOptions";
        }
        "$select" => {
            parameterName += "SelectOptions";
        }
        "$expand" => {
            parameterName += "ExpandOptions";
        }
        "$search" => {
            parameterName += "SearchOptions";
        }
        "$orderby" => {
            parameterName += "OrderByOptions";
        }
        _ => {
            io:println("Error: Invalid parameter name: " + parameterName);
        }
    }

    return parameterName;
}

function sanitizeSchemaNames(string apiName, string specPath) returns error? {
    // Directory name = api name
    // File name = api_name.json
    json openAPISpec = check io:fileReadJson(specPath);

    Specification spec = check openAPISpec.cloneWithType(Specification);

    map<json> updatedSchemas = {};
    map<string> updatedNames = {};

    foreach [string, json] [schemaName, schema] in spec.components.schemas.entries() {
        boolean schemaNameCheck = schemaName.includes(".");
        if schemaNameCheck {
            string updatedKey = getSanitizedSchemaName(schemaName);
            updatedSchemas[updatedKey] = schema;
            updatedNames[schemaName] = updatedKey;
        } else {
            updatedSchemas[schemaName] = schema;
        }
    }
    spec.components.schemas = updatedSchemas;

    string updatedSpec = spec.toJsonString();
    foreach [string, string] [oldName, newName] in updatedNames.entries() {
        string sanitizedOldNameRegex = re `\.`.replace(oldName, "\\.");
        regexp:RegExp regexp = re `${sanitizedOldNameRegex}"`;
        updatedSpec = regexp.replaceAll(updatedSpec, newName + "\"");
    }

    check io:fileWriteString(specPath, updatedSpec);
}

function getSanitizedSchemaName(string schemaName) returns string {
    int? indexOfPeriod = schemaName.lastIndexOf(".");
    int substringStartIndex = indexOfPeriod == () ? 0 : indexOfPeriod + 1;
    string updatedKey = schemaName.substring(substringStartIndex);

    if updatedKey.endsWith("_Type") {
        updatedKey = updatedKey.substring(0, updatedKey.length() - 5);
    }

    if updatedKey.endsWith("_Type-create") {
        updatedKey = "Create" + updatedKey.substring(0, updatedKey.length() - 12);
    }

    if updatedKey.endsWith("_Type-update") {
        updatedKey = "Update" + updatedKey.substring(0, updatedKey.length() - 12);
    }

    if updatedKey.endsWith("Type") {
        updatedKey = updatedKey.substring(0, updatedKey.length() - 4);
    }

    if updatedKey.endsWith("Type-create") {
        updatedKey = "Create" + updatedKey.substring(0, updatedKey.length() - 11);
    }

    if updatedKey.endsWith("Type-update") {
        updatedKey = "Update" + updatedKey.substring(0, updatedKey.length() - 11);
    }

    if updatedKey.endsWith("-create") {
        updatedKey = "Create" + updatedKey.substring(0, updatedKey.length() - 7);
    }

    if updatedKey.endsWith("-update") {
        updatedKey = "Update" + updatedKey.substring(0, updatedKey.length() - 7);
    }
    return updatedKey;
}

function sanitizResponseSchemaNames(string specPath) returns error? {
    json openAPISpec = check io:fileReadJson(specPath);
    Specification spec = check openAPISpec.cloneWithType(Specification);
    boolean isODATA4 = false;
    if (spec.x\-sap\-api\-type=="ODATAV4"){
        isODATA4 = true;
    }
    map<Path> paths = spec.paths;
    foreach var [key,value] in paths.entries() {
        if value.get != () {
            Get getPath = value.get ?: {parameters: []};
            map<ResponseCode> responses = getPath.responses ?: {};
            foreach [string,ResponseCode] [_,item] in responses.entries() {
                if item.description == "Retrieved entities" {
                    map<ResponseHeader> content = item.content ?: {};
                    if content.hasKey("application/json"){
                        ResponseHeader app = content["application/json"] ?: {};
                        ResponseSchema schema = app.schema ?: {};
                        if !isODATA4 {
                            ResponseProperties properties = schema.properties["d"] ?: {properties: ()};
                            string prefix = properties.title ?: string ``;
                            prefix =prefix.trim();
                            if prefix.startsWith("Collection of"){
                                prefix = prefix.substring(14,prefix.length());
                                prefix = "CollectionOf"+prefix;
                            }
                            if prefix.endsWith("Type"){
                                prefix = prefix.substring(0,prefix.length()-4);
                            }
                            schema.title = prefix+"Wrapper";
                        }
                        else {
                            string schemaTitle = schema.title?: string ``;
                            if schemaTitle.startsWith("Collection of"){
                                schema.title = "CollectionOf"+schemaTitle.substring(14,schemaTitle.length()-5);
                            }
                        }
                    }
                }
                else if item.description == "Retrieved entity" {
                    map<ResponseHeader> content = item.content ?: {};
                    if content.hasKey("application/json"){
                        ResponseHeader app = content["application/json"] ?: {};
                        ResponseSchema schema = app.schema ?: {};
                        string schemaTitle = schema.title ?:string `` ;
                        if schemaTitle.endsWith("Type"){
                            schema.title = schemaTitle.substring(0,schemaTitle.length()-4);
                        }
                    } 
                }
            }
        }
        if value.post != () {
            Post postPath = value.post ?: {parameters: []};
            map<ResponseCode> responses = postPath.responses ?: {};
            foreach [string,ResponseCode] [_,item] in responses.entries() {
                if item.description == "Created entity"{
                    map<ResponseHeader> content = item.content ?: {};
                    if content.hasKey("application/json"){
                        ResponseHeader app = content["application/json"] ?: {};
                        ResponseSchema schema = app.schema ?: {};
                        string schemaTitle = schema.title ?: string ``;
                        if schemaTitle == "Wrapper"{
                            schemaTitle = key.substring(1,key.length())+"Wrapper";
                            schema.title = schemaTitle;
                        }
                        else if schemaTitle.endsWith("Type") {
                            schema.title = schemaTitle.substring(0,schemaTitle.length()-4);
                        }
                    }
                }

            }
        }
    }
    check io:fileWriteJson(specPath, spec.toJson());
};