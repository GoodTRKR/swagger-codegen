package io.swagger.codegen.languages;

import io.swagger.codegen.CliOption;
import io.swagger.codegen.CodegenConfig;
import io.swagger.codegen.CodegenProperty;
import io.swagger.codegen.CodegenType;
import io.swagger.codegen.DefaultCodegen;
import io.swagger.codegen.SupportingFile;
import io.swagger.models.properties.ArrayProperty;
import io.swagger.models.properties.MapProperty;
import io.swagger.models.properties.Property;

import java.io.File;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;


public class FotitionClientCodegen extends DefaultCodegen implements CodegenConfig {

    protected Set<String> foundationClasses = new HashSet<String>();
    protected String sourceFolder = "fotition-objc-client";
    protected String classPrefix = "FT";
    protected String projectName = "fotition-objc-client";

    public FotitionClientCodegen() {
        outputFolder = "generated-code" + File.separator + "fotition-objc";
        modelTemplateFiles.put("model-header.mustache", ".h");
        modelTemplateFiles.put("model-body.mustache", ".m");
        apiTemplateFiles.put("api-header.mustache", ".h");
        apiTemplateFiles.put("api-body.mustache", ".m");
        templateDir = "fotition-objc";
        modelPackage = "";

        defaultIncludes = new HashSet<String>(
                Arrays.asList(
                        "bool",
                        "BOOL",
                        "int",
                        "NSString",
                        "NSObject",
                        "NSArray",
                        "NSNumber",
                        "NSDate",
                        "NSDictionary",
                        "NSMutableArray",
                        "NSMutableDictionary")
        );
        languageSpecificPrimitives = new HashSet<String>(
                Arrays.asList(
                        "NSNumber",
                        "NSString",
                        "NSObject",
                        "NSDate",
                        "bool",
                        "BOOL")
        );

        // ref: http://www.tutorialspoint.com/objective_c/objective_c_basic_syntax.htm
        reservedWords = new HashSet<String>(
                Arrays.asList(
                        "auto", "else", "long", "switch",
                        "break", "enum", "register", "typedef",
                        "case", "extern", "return", "union",
                        "char", "float", "short", "unsigned",
                        "const", "for", "signed", "void",
                        "continue", "goto", "sizeof", "volatile",
                        "default", "if", "id", "static", "while",
                        "do", "int", "struct", "_Packed",
                        "double", "protocol", "interface", "implementation",
                        "NSObject", "NSInteger", "NSNumber", "CGFloat",
                        "property", "nonatomic", "retain", "strong",
                        "weak", "unsafe_unretained", "readwrite", "readonly"
                ));

        typeMapping = new HashMap<String, String>();
        typeMapping.put("enum", "NSString");
        typeMapping.put("Date", "NSDate");
        typeMapping.put("DateTime", "NSDate");
        typeMapping.put("boolean", "NSNumber");
        typeMapping.put("string", "NSString");
        typeMapping.put("integer", "NSNumber");
        typeMapping.put("int", "NSNumber");
        typeMapping.put("float", "NSNumber");
        typeMapping.put("long", "NSNumber");
        typeMapping.put("double", "NSNumber");
        typeMapping.put("array", "NSArray");
        typeMapping.put("map", "NSDictionary");
        typeMapping.put("number", "NSNumber");
        typeMapping.put("List", "NSArray");
        typeMapping.put("object", "NSObject");

        importMapping = new HashMap<String, String>();

        foundationClasses = new HashSet<String>(
                Arrays.asList(
                        "NSNumber",
                        "NSObject",
                        "NSString",
                        "NSDate",
                        "NSDictionary")
        );

        instantiationTypes.put("array", "NSMutableArray");
        instantiationTypes.put("map", "NSMutableDictionary");

        cliOptions.add(new CliOption("classPrefix", "prefix for generated classes"));
        cliOptions.add(new CliOption("sourceFolder", "source folder for generated code"));
        cliOptions.add(new CliOption("projectName", "name of the Xcode project in generated Podfile"));
    }

    public CodegenType getTag() {
        return CodegenType.CLIENT;
    }

    public String getName() {
        return "fotition-objc";
    }

    public String getHelp() {
        return "Generates an Objective-C client library for Fotition.";
    }

    @Override
    public void processOpts() {
        super.processOpts();

        if (additionalProperties.containsKey("sourceFolder")) {
            this.setSourceFolder((String) additionalProperties.get("sourceFolder"));
        }

        if (additionalProperties.containsKey("classPrefix")) {
            this.setClassPrefix((String) additionalProperties.get("classPrefix"));
        }

        if (additionalProperties.containsKey("projectName")) {
            this.setProjectName((String) additionalProperties.get("projectName"));
        } else {
            additionalProperties.put("projectName", projectName);
        }

        supportingFiles.add(new SupportingFile("FTObject.h", sourceFolder, "FTObject.h"));
        supportingFiles.add(new SupportingFile("FTObject.m", sourceFolder, "FTObject.m"));
        supportingFiles.add(new SupportingFile("FTQueryParamCollection.h", sourceFolder, "FTQueryParamCollection.h"));
        supportingFiles.add(new SupportingFile("FTQueryParamCollection.m", sourceFolder, "FTQueryParamCollection.m"));
        supportingFiles.add(new SupportingFile("FotitionAPIClient.h", sourceFolder, "FotitionAPIClient.h"));
        supportingFiles.add(new SupportingFile("FotitionAPIClient.m", sourceFolder, "FotitionAPIClient.m"));
        supportingFiles.add(new SupportingFile("FTFile.h", sourceFolder, "FTFile.h"));
        supportingFiles.add(new SupportingFile("FTFile.m", sourceFolder, "FTFile.m"));
        supportingFiles.add(new SupportingFile("JSONValueTransformer+ISO8601.m", sourceFolder, "JSONValueTransformer+ISO8601.m"));
        supportingFiles.add(new SupportingFile("JSONValueTransformer+ISO8601.h", sourceFolder, "JSONValueTransformer+ISO8601.h"));
        supportingFiles.add(new SupportingFile("FTConfiguration-body.mustache", sourceFolder, "FTConfiguration.m"));
        supportingFiles.add(new SupportingFile("FTConfiguration-header.mustache", sourceFolder, "FTConfiguration.h"));
        supportingFiles.add(new SupportingFile("Podfile.mustache", "", "Podfile"));
    }

    @Override
    public String toInstantiationType(Property p) {
        if (p instanceof MapProperty) {
            MapProperty ap = (MapProperty) p;
            String inner = getSwaggerType(ap.getAdditionalProperties());
            return instantiationTypes.get("map");
        } else if (p instanceof ArrayProperty) {
            ArrayProperty ap = (ArrayProperty) p;
            String inner = getSwaggerType(ap.getItems());
            return instantiationTypes.get("array");
        } else {
            return null;
        }
    }

    @Override
    public String getTypeDeclaration(String name) {
        if (languageSpecificPrimitives.contains(name) && !foundationClasses.contains(name)) {
            return name;
        } else {
            return name + "*";
        }
    }

    @Override
    public String getSwaggerType(Property p) {
        String swaggerType = super.getSwaggerType(p);
        String type = null;
        if (typeMapping.containsKey(swaggerType)) {
            type = typeMapping.get(swaggerType);
            if (languageSpecificPrimitives.contains(type) && !foundationClasses.contains(type)) {
                return toModelName(type);
            }
        } else {
            type = swaggerType;
        }
        return toModelName(type);
    }

    @Override
    public String getTypeDeclaration(Property p) {
        if (p instanceof ArrayProperty) {
            ArrayProperty ap = (ArrayProperty) p;
            Property inner = ap.getItems();
            String innerType = getSwaggerType(inner);

            // In this codition, type of property p is array of primitive,
            // return container type with pointer, e.g. `NSArray*'
            if (languageSpecificPrimitives.contains(innerType)) {
                return getSwaggerType(p) + "*";
            }

            // In this codition, type of property p is array of model,
            // return container type combine inner type with pointer, e.g. `NSArray<FTTag>*'
            String innerTypeDeclaration = getTypeDeclaration(inner);

            if (innerTypeDeclaration.endsWith("*")) {
                innerTypeDeclaration = innerTypeDeclaration.substring(0, innerTypeDeclaration.length() - 1);
            }

            return getSwaggerType(p) + "<" + innerTypeDeclaration + ">*";
        } else {
            String swaggerType = getSwaggerType(p);

            // In this codition, type of p is objective-c primitive type, e.g. `NSSNumber',
            // return type of p with pointer, e.g. `NSNumber*'
            if (languageSpecificPrimitives.contains(swaggerType) &&
                    foundationClasses.contains(swaggerType)) {
                return swaggerType + "*";
            }
            // In this codition, type of p is c primitive type, e.g. `bool',
            // return type of p, e.g. `bool'
            else if (languageSpecificPrimitives.contains(swaggerType)) {
                return swaggerType;
            }
            // In this codition, type of p is objective-c object type, e.g. `FTPet',
            // return type of p with pointer, e.g. `FTPet*'
            else {
                return swaggerType + "*";
            }
        }
    }

    @Override
    public String toModelName(String type) {
        type = type.replaceAll("[^0-9a-zA-Z_]", "_");

        // language build-in classes
        if (typeMapping.keySet().contains(type) ||
                foundationClasses.contains(type) ||
                importMapping.values().contains(type) ||
                defaultIncludes.contains(type) ||
                languageSpecificPrimitives.contains(type)) {
            return camelize(type);
        }
        // custom classes
        else {
            return classPrefix + camelize(type);
        }
    }

    @Override
    public String toModelFilename(String name) {
        // should be the same as the model name
        return toModelName(name);
    }

    @Override
    protected void setNonArrayMapProperty(CodegenProperty property, String type) {
        super.setNonArrayMapProperty(property, type);
        if ("NSDictionary".equals(type)) {
            property.setter = "initWithDictionary";
        } else {
            property.setter = "initWithValues";
        }
    }

    @Override
    public String toModelImport(String name) {
        if ("".equals(modelPackage())) {
            return name;
        } else {
            return modelPackage() + "." + name;
        }
    }

    @Override
    public String toDefaultValue(Property p) {
        return null;
    }

    @Override
    public String apiFileFolder() {
        return outputFolder + File.separator + sourceFolder;
    }

    @Override
    public String modelFileFolder() {
        return outputFolder + File.separator + sourceFolder;
    }

    @Override
    public String toApiName(String name) {
        return classPrefix + camelize(name) + "Api";
    }

    public String toApiFilename(String name) {
        return classPrefix + camelize(name) + "Api";
    }

    @Override
    public String toVarName(String name) {
        // replace non-word characters to `_`
        // e.g. `created-at` to `created_at`
        name = name.replaceAll("[^a-zA-Z0-9_]", "_");

        // if it's all upper case, do noting
        if (name.matches("^[A-Z_]$")) {
            return name;
        }

        // camelize (lower first character) the variable name
        // e.g. `pet_id` to `petId`
        name = camelize(name, true);

        // for reserved word or word starting with number, prepend `_`
        if (reservedWords.contains(name) || name.matches("^\\d.*")) {
            name = escapeReservedWord(name);
        }

        return name;
    }

    @Override
    public String toParamName(String name) {
        // should be the same as variable name
        return toVarName(name);
    }

    public String escapeReservedWord(String name) {
        return "_" + name;
    }

    @Override
    public String toOperationId(String operationId) {
        // method name cannot use reserved keyword, e.g. return
        if (reservedWords.contains(operationId)) {
            throw new RuntimeException(operationId + " (reserved word) cannot be used as method name");
        }

        return camelize(operationId, true);
    }

    public void setSourceFolder(String sourceFolder) {
        this.sourceFolder = sourceFolder;
    }

    public void setClassPrefix(String classPrefix) {
        this.classPrefix = classPrefix;
    }

    public void setProjectName(String projectName) {
        this.projectName = projectName;
    }
}
