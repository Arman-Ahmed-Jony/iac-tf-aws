#!/usr/bin/env python3
"""
Generic Terraform state visualizer.
Reads any terraform.tfstate and generates an HTML page with a Mermaid diagram.

Usage:
    python3 visualize.py [tfstate_file]

    Defaults to ./terraform.tfstate if no argument is given.
    Outputs: infra-diagram.html
"""

import json
import sys
import os

# ── Icons ──────────────────────────────────────────────────────────────────────
ICONS = {
    "aws_vpc":                     "☁️",
    "aws_subnet":                  "🔵",
    "aws_internet_gateway":        "🔀",
    "aws_nat_gateway":             "🔀",
    "aws_route_table":             "📋",
    "aws_route":                   "➡️",
    "aws_route_table_association": "🔗",
    "aws_security_group":          "🛡️",
    "aws_instance":                "🖥️",
    "aws_key_pair":                "🔑",
    "tls_private_key":             "🔐",
    "local_file":                  "📄",
    "aws_eip":                     "🌐",
    "aws_lb":                      "⚖️",
    "aws_lb_target_group":         "🎯",
    "aws_lb_listener":             "👂",
    "aws_s3_bucket":               "🪣",
    "aws_iam_role":                "👤",
    "aws_iam_instance_profile":    "👤",
    "aws_db_instance":             "🗄️",
    "aws_elasticache_cluster":     "⚡",
    "aws_cloudfront_distribution": "🌍",
    "aws_lambda_function":         "λ",
}

# ── Key attributes to show in node label ──────────────────────────────────────
LABEL_ATTRS = {
    "aws_vpc":                     ["cidr_block"],
    "aws_subnet":                  ["cidr_block", "availability_zone"],
    "aws_internet_gateway":        [],
    "aws_nat_gateway":             [],
    "aws_route_table":             [],
    "aws_route":                   ["destination_cidr_block"],
    "aws_route_table_association": [],
    "aws_security_group":          ["name"],
    "aws_instance":                ["instance_type", "public_ip", "private_ip", "instance_state"],
    "aws_key_pair":                ["key_name"],
    "tls_private_key":             ["algorithm"],
    "local_file":                  ["filename"],
    "aws_eip":                     ["public_ip"],
    "aws_lb":                      ["name", "dns_name"],
    "aws_db_instance":             ["identifier", "engine", "instance_class"],
    "aws_s3_bucket":               ["bucket"],
    "aws_lambda_function":         ["function_name", "runtime"],
}

# ── Mermaid CSS class per resource type ───────────────────────────────────────
STYLE_CLASS = {
    "aws_vpc":                     "vpc",
    "aws_subnet":                  "subnet",
    "aws_internet_gateway":        "vpc",
    "aws_nat_gateway":             "vpc",
    "aws_route_table":             "rt",
    "aws_route":                   "rt",
    "aws_route_table_association": "rt",
    "aws_security_group":          "sg",
    "aws_instance":                "ec2",
    "aws_key_pair":                "key",
    "tls_private_key":             "key",
    "local_file":                  "file",
    "aws_eip":                     "inet",
    "aws_lb":                      "ec2",
    "aws_lb_target_group":         "ec2",
    "aws_lb_listener":             "ec2",
    "aws_db_instance":             "db",
    "aws_s3_bucket":               "file",
    "aws_iam_role":                "key",
    "aws_iam_instance_profile":    "key",
    "aws_lambda_function":         "ec2",
    "aws_cloudfront_distribution": "inet",
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_state(path):
    with open(path) as f:
        return json.load(f)


def addr_to_node_id(addr):
    """Convert a resource address to a valid Mermaid node ID."""
    return (
        addr.replace(".", "_")
            .replace("-", "_")
            .replace("[", "_")
            .replace("]", "_")
            .replace("/", "_")
    )


def short_val(val, maxlen=24):
    s = str(val) if val is not None else ""
    return s[:maxlen] + "…" if len(s) > maxlen else s


def resource_address(r):
    mod  = r.get("module", "")
    rtype = r["type"]
    name  = r["name"]
    return f"{mod}.{rtype}.{name}" if mod else f"{rtype}.{name}"


def friendly_label(r):
    """
    Build a multi-line Mermaid label for a resource.
    Lines are joined with \\n (Mermaid line break inside node label).
    """
    rtype = r["type"]
    name  = r["name"]
    mod   = r.get("module", "")
    attrs = r["instances"][0]["attributes"] if r.get("instances") else {}

    icon       = ICONS.get(rtype, "📦")
    type_label = rtype.replace("aws_", "").replace("_", " ").title()

    # Friendly short name: strip "module." prefix from each segment
    mod_parts  = [p.replace("module.", "") for p in mod.split(".") if p and p != "module"]
    mod_parts.append(name)
    friendly   = " / ".join(mod_parts)

    lines = [f"{icon} {type_label}", friendly]

    # Append configured key attributes
    for attr in LABEL_ATTRS.get(rtype, []):
        val = attrs.get(attr)
        if val not in (None, "", []):
            lines.append(f"{attr}: {short_val(val)}")

    # Always append the AWS resource ID
    rid = attrs.get("id", "")
    if rid and rtype.startswith("aws_"):
        lines.append(short_val(rid))

    return "\\n".join(lines)


def compute_direct_deps(all_instances):
    """
    For each resource, remove transitive dependencies so we only draw
    direct edges (keeps the diagram readable).

    A dependency D of resource R is *transitive* if D is already a
    dependency of some other dependency of R.
    """
    raw = {addr: set(inst.get("dependencies", [])) for addr, inst in all_instances.items()}

    direct = {}
    for addr, deps in raw.items():
        # Collect everything that is reachable from the deps themselves
        transitive = set()
        for dep in deps:
            transitive.update(raw.get(dep, set()))
        # Keep only deps that are NOT covered transitively
        direct[addr] = [d for d in deps if d not in transitive]

    return direct


# ── Diagram builder ───────────────────────────────────────────────────────────

def build_diagram(state):
    resources = state.get("resources", [])

    # Build lookups keyed by resource address
    all_resources = {}
    all_instances  = {}

    for r in resources:
        if not r.get("instances"):
            continue
        addr = resource_address(r)
        all_resources[addr] = r
        all_instances[addr]  = r["instances"][0]

    direct_deps = compute_direct_deps(all_instances)

    lines  = ["flowchart TD"]
    styles = {}  # node_id -> css class

    # ── Nodes ────────────────────────────────────────────────────────────────
    for addr, r in all_resources.items():
        node_id        = addr_to_node_id(addr)
        label          = friendly_label(r)
        cls            = STYLE_CLASS.get(r["type"], "default")
        styles[node_id] = cls
        lines.append(f'    {node_id}["{label}"]')

    lines.append("")

    # ── Edges (dependency → dependant) ──────────────────────────────────────
    for addr, deps in direct_deps.items():
        src = addr_to_node_id(addr)
        for dep in deps:
            if dep in all_resources:
                tgt = addr_to_node_id(dep)
                lines.append(f"    {tgt} --> {src}")

    # ── Class definitions ────────────────────────────────────────────────────
    lines += [
        "",
        "    classDef vpc     fill:#e8f4f8,stroke:#2196F3,color:#000,stroke-width:2px",
        "    classDef subnet  fill:#e8f8e8,stroke:#4CAF50,color:#000,stroke-width:2px",
        "    classDef ec2     fill:#fff8e1,stroke:#FF9800,color:#000,stroke-width:2px",
        "    classDef sg      fill:#fce4ec,stroke:#E91E63,color:#000,stroke-width:2px",
        "    classDef key     fill:#f3e5f5,stroke:#9C27B0,color:#000,stroke-width:2px",
        "    classDef inet    fill:#e3f2fd,stroke:#1565C0,color:#000,stroke-width:2px",
        "    classDef rt      fill:#e8eaf6,stroke:#3F51B5,color:#000,stroke-width:2px",
        "    classDef file    fill:#f1f8e9,stroke:#558B2F,color:#000,stroke-width:2px",
        "    classDef db      fill:#fbe9e7,stroke:#BF360C,color:#000,stroke-width:2px",
        "    classDef default fill:#f5f5f5,stroke:#9e9e9e,color:#000,stroke-width:1px",
        "",
    ]

    # Assign classes to nodes
    by_class = {}
    for node_id, cls in styles.items():
        by_class.setdefault(cls, []).append(node_id)

    for cls, nodes in by_class.items():
        lines.append(f"    class {','.join(nodes)} {cls}")

    return "\n".join(lines)


# ── Outputs panel ─────────────────────────────────────────────────────────────

def render_outputs(outputs):
    if not outputs:
        return ""

    cards = []
    colors = ["blue", "green", "orange", "purple", "teal", "red"]
    for i, (key, meta) in enumerate(outputs.items()):
        val   = meta.get("value", "")
        color = colors[i % len(colors)]
        cards.append(f"""
        <div class="output-card {color}">
          <label>{key}</label>
          <code>{val}</code>
        </div>""")

    return f"""
  <h2>Outputs</h2>
  <div class="outputs">{''.join(cards)}
  </div>"""


# ── Resource summary table ────────────────────────────────────────────────────

def render_summary(state):
    from collections import Counter
    counts = Counter(r["type"] for r in state.get("resources", []) if r.get("instances"))
    rows = "".join(
        f"<tr><td>{rtype}</td><td>{count}</td></tr>"
        for rtype, count in sorted(counts.items())
    )
    return f"""
  <h2>Resources ({sum(counts.values())} total)</h2>
  <table>
    <thead><tr><th>Type</th><th>Count</th></tr></thead>
    <tbody>{rows}</tbody>
  </table>"""


# ── HTML renderer ─────────────────────────────────────────────────────────────

def render_html(diagram, state, source_file):
    tf_version = state.get("terraform_version", "unknown")
    serial     = state.get("serial", "?")
    outputs    = state.get("outputs", {})

    outputs_html = render_outputs(outputs)
    summary_html = render_summary(state)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Terraform Infra Diagram</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f0f2f5;
      color: #222;
      padding: 28px 32px;
      line-height: 1.5;
    }}

    h1 {{
      font-size: 1.7rem;
      font-weight: 700;
      color: #1a1a2e;
    }}
    h2 {{
      font-size: 1.1rem;
      font-weight: 600;
      margin: 28px 0 12px;
      color: #333;
    }}
    .meta {{
      color: #666;
      font-size: 0.85rem;
      margin-top: 4px;
      margin-bottom: 28px;
    }}

    /* ── Outputs ── */
    .outputs {{
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
      gap: 14px;
      margin-bottom: 8px;
    }}
    .output-card {{
      background: #fff;
      border-radius: 10px;
      padding: 14px 18px;
      box-shadow: 0 1px 6px rgba(0,0,0,0.07);
      border-left: 4px solid #2196F3;
    }}
    .output-card.blue   {{ border-color: #2196F3; }}
    .output-card.green  {{ border-color: #4CAF50; }}
    .output-card.orange {{ border-color: #FF9800; }}
    .output-card.purple {{ border-color: #9C27B0; }}
    .output-card.teal   {{ border-color: #009688; }}
    .output-card.red    {{ border-color: #E53935; }}
    .output-card label {{
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: #888;
      display: block;
      margin-bottom: 5px;
    }}
    .output-card code {{
      font-size: 0.82rem;
      word-break: break-all;
      background: #f5f7fa;
      padding: 4px 8px;
      border-radius: 4px;
      display: block;
    }}

    /* ── Summary table ── */
    table {{
      width: 100%;
      max-width: 480px;
      border-collapse: collapse;
      background: #fff;
      border-radius: 10px;
      overflow: hidden;
      box-shadow: 0 1px 6px rgba(0,0,0,0.07);
      margin-bottom: 8px;
    }}
    th, td {{
      padding: 10px 16px;
      text-align: left;
      font-size: 0.88rem;
      border-bottom: 1px solid #f0f0f0;
    }}
    th {{
      background: #f5f7fa;
      font-weight: 600;
      color: #555;
    }}
    tr:last-child td {{ border-bottom: none; }}

    /* ── Diagram ── */
    .diagram-box {{
      background: #fff;
      border-radius: 12px;
      padding: 32px;
      box-shadow: 0 2px 12px rgba(0,0,0,0.08);
      margin-top: 28px;
      overflow-x: auto;
    }}
    .mermaid svg {{ max-width: 100%; height: auto; }}
  </style>
</head>
<body>
  <h1>Terraform Infrastructure Diagram</h1>
  <p class="meta">
    Source: <strong>{source_file}</strong> &nbsp;·&nbsp;
    Terraform: <strong>{tf_version}</strong> &nbsp;·&nbsp;
    State serial: <strong>{serial}</strong>
  </p>

  {outputs_html}

  {summary_html}

  <div class="diagram-box">
    <div class="mermaid">
{diagram}
    </div>
  </div>

  <script>
    mermaid.initialize({{
      startOnLoad: true,
      theme: 'default',
      flowchart: {{ curve: 'basis', padding: 20 }},
    }});
  </script>
</body>
</html>
"""


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    tfstate_path = sys.argv[1] if len(sys.argv) > 1 else "terraform.tfstate"

    if not os.path.exists(tfstate_path):
        print(f"Error: file not found — {tfstate_path}")
        sys.exit(1)

    state   = load_state(tfstate_path)
    diagram = build_diagram(state)
    html    = render_html(diagram, state, source_file=os.path.basename(tfstate_path))

    out_path = "infra-diagram.html"
    with open(out_path, "w") as f:
        f.write(html)

    resource_count = sum(1 for r in state.get("resources", []) if r.get("instances"))
    print(f"✅  Diagram generated: {out_path}")
    print(f"    Resources visualized: {resource_count}")
    print(f"    Open in browser:  open {out_path}")


if __name__ == "__main__":
    main()
