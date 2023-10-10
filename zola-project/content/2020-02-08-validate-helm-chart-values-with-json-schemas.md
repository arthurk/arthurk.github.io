+++
title = "Validating Helm Chart Values with JSON Schemas"
date = "2020-02-08"
+++

Helm v3 [added support](https://github.com/helm/helm/pull/5350) to validate values in a chart's `values.yaml` file with [JSON schemas](https://json-schema.org/). It allows us to do:

*   Requirement checks. Example: An `API_KEY` environment variable is set
*   Type validation. Example: The image tag is a string such as `"1.5"` and not the number `1.5`
*   Range validation. Example: The value for a CPU utilization percentage key is between 1 and 100
*   Constraint Validation. Example: The `pullPolicy` is `IfNotPresent`, `Always`, or `Never`; A URL has the format `http(s)://<host>:<port>`

In this post I'm going to show how to create a JSON schema and use it to validate a chart's `values.yaml` file. After that I'm going to show how to automatically generate a schema from an existing values file.

Example
-------

For this example I'm using the chart that is created when running `helm create mychart`. We'll create a JSON schema that will validate that the following conditions are met:

*   `image.repository` is a valid docker image name
*   `image.pullPolicy` is `IfNotPresent`, `Always` or `Never`

The relevant part in the `values.yaml` file is:

```yaml
image:
  repository: my-docker-image
  pullPolicy: IfNotPresent
```

The JSON schema needs to be in a file named `values.schema.json`. It has to be located in the same directory as the `values.yaml` file. To match the requirements from above the file needs to have the following content:

```json
{
  "$schema": "http://json-schema.org/schema#",
  "type": "object",
  "required": [
    "image"
  ],
  "properties": {
    "image": {
      "type": "object",
      "required": [
        "repository",
        "pullPolicy"
      ],
      "properties": {
        "repository": {
          "type": "string",
          "pattern": "^[a-z0-9-_]+$"
        },
        "pullPolicy": {
          "type": "string",
          "pattern": "^(Always|Never|IfNotPresent)$"
        }
      }
    }
  }
}
```

Note that putting a key in the `required` array does not mean that it has a value. In YAML if a key doesn't have a value it will be set to an empty string. To make sure the value was set, a regex for the `pattern` key has to be added that matches a non-empty string.

To demonstrate that the validation is working I'm leaving the `repo` empty and set `pullPolicy` to an invalid value. Running lint shows the following output:

```
$ helm lint .

==> Linting .
[ERROR] values.yaml: - image.repository: Invalid type. Expected: string, given: null
- image.pullPolicy: Does not match pattern '^(Always|Never|IfNotPresent)$'

[ERROR] templates/: values don't meet the specifications of the schema(s) in the following chart(s):
mychart:
- image.repository: Invalid type. Expected: string, given: null
- image.pullPolicy: Does not match pattern '^(Always|Never|IfNotPresent)$'

Error: 1 chart(s) linted, 1 chart(s) failed
```

The schema is automatically validated when running the following commands:

*   helm install
*   helm upgrade
*   helm lint
*   helm template

The YAML values and the JSON schema need to be kept in sync manually. Helm will not check if keys from the YAML values file are missing from the schema. It will only validate fields that are specified in the schema.

Creating a JSON Schema for existing YAML values
-----------------------------------------------

We can infer a schema from existing YAML values and use it as a starting point when writing a new schema. The steps are:

1.  Convert your values YAML file to JSON on [https://www.json2yaml.com/](https://www.json2yaml.com/)
2.  Paste the JSON on [https://www.jsonschema.net/](https://www.jsonschema.net) and click on "Infer Schema"
3.  Paste the schema into the `values.schema.json` file

We can run `helm lint` to make sure the schema has been generated correctly:

```
$ helm lint mychart/

==> Linting .

1 chart(s) linted, 0 chart(s) failed
```

The inferred schema will mark all keys as required and set their type. A regex can be added to keys to make sure they have a value set. The `id`, `title`, `default` and `examples` fields are not necessary for validating helm charts and can be removed.
