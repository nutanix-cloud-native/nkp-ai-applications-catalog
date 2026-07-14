# Expand the placeholder strings that parameterize.sh injects into a baked
# manifest into Helm template expressions, producing the chart template file.
#
# The placeholders are valid YAML while injected (so yq can keep reading and
# writing the file); this pass is what finally turns the file into a Helm
# template. Two shapes:
#
#   Block  (map/list field; empty override falls back to upstream):
#     <indent>__HELMBLOCK__<key>__<field>: ""
#       -> {{- with .Values.workloads.<key>.<field> }}
#          <field>:
#            {{- toYaml . | nindent <indent+2> }}
#          {{- end }}
#
#   Scalar (e.g. replicas, seeded with the upstream default):
#     <indent><field>: __HELMSCALAR__<key>__<field>__<default>
#       -> <field>: {{ .Values.workloads.<key>.<field> | default <default> }}
#
# Indentation is read from the placeholder line, so output matches yq's emitted
# indent. <key> is alphanumeric-only so the "__" delimiter splits cleanly.
{
  line = $0

  if (match(line, /^[[:space:]]*__HELMBLOCK__[A-Za-z0-9]+__[A-Za-z]+:/)) {
    indent = match(line, /[^ ]/) - 1
    indent_str = substr(line, 1, indent)
    stripped = line
    sub(/^[[:space:]]*__HELMBLOCK__/, "", stripped)
    sub(/:.*$/, "", stripped)
    split(stripped, parts, "__")
    key = parts[1]; field = parts[2]
    printf "%s{{- with .Values.workloads.%s.%s }}\n", indent_str, key, field
    printf "%s%s:\n", indent_str, field
    printf "%s  {{- toYaml . | nindent %d }}\n", indent_str, indent + 2
    printf "%s{{- end }}\n", indent_str
    next
  }

  if (match(line, /__HELMSCALAR__/)) {
    indent = match(line, /[^ ]/) - 1
    indent_str = substr(line, 1, indent)
    field_name = line; sub(/:.*/, "", field_name); sub(/^[[:space:]]*/, "", field_name)
    token = line; sub(/^.*__HELMSCALAR__/, "", token); sub(/"?[[:space:]]*$/, "", token)
    split(token, parts, "__")
    key = parts[1]; field = parts[2]; def = parts[3]
    printf "%s%s: {{ .Values.workloads.%s.%s | default %s }}\n", indent_str, field_name, key, field, def
    next
  }

  # Pass-through line. Escape any literal '{{' (e.g. Argo placeholders like
  # {{workflow.uid}} baked into ConfigMaps/args) so Helm emits it verbatim. Our
  # own expressions are printed above and never reach here; gsub doesn't re-scan
  # its replacement, so the '{{' we insert isn't re-escaped.
  gsub(/\{\{/, "{{ \"{{\" }}", line)
  print line
}
