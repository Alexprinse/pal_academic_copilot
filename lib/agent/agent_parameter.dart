enum AgentParameterType {
  string,
  number,
  integer,
  boolean,
  array,
  object,
}

class AgentValidationResult {
  final bool isValid;
  final String? error;

  const AgentValidationResult.valid()
      : isValid = true,
        error = null;

  const AgentValidationResult.invalid(this.error) : isValid = false;
}

class AgentParameter {
  final String name;
  final AgentParameterType type;
  final String description;
  final bool required;
  final dynamic defaultValue;
  final List<String>? allowedValues;

  const AgentParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.allowedValues,
  });

  Map<String, dynamic> toSchema() {
    return {
      'type': type.name,
      'description': description,
      if (defaultValue != null) 'default': defaultValue,
      if (allowedValues != null) 'enum': allowedValues,
    };
  }

  AgentValidationResult validate(dynamic value) {
    if (value == null) {
      if (required) {
        return AgentValidationResult.invalid(
            'Missing required parameter: "$name"');
      }
      return const AgentValidationResult.valid();
    }

    switch (type) {
      case AgentParameterType.string:
        if (value is! String) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be a string');
        }
        if (allowedValues != null && !allowedValues!.contains(value)) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be one of: ${allowedValues!.join(", ")}');
        }
        break;

      case AgentParameterType.integer:
        if (value is! int) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be an integer');
        }
        break;

      case AgentParameterType.number:
        if (value is! num) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be a number');
        }
        break;

      case AgentParameterType.boolean:
        if (value is! bool) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be a boolean');
        }
        break;

      case AgentParameterType.array:
        if (value is! List) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be a list');
        }
        break;

      case AgentParameterType.object:
        if (value is! Map) {
          return AgentValidationResult.invalid(
              'Parameter "$name" must be a map');
        }
        break;
    }

    return const AgentValidationResult.valid();
  }
}
