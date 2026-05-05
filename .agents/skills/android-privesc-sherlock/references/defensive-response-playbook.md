# Android Privesc Sherlock — Defensive Response Playbook

Use this reference when the user asks for hardening, incident response, enterprise triage, control prioritization, or "what should we do about this?"

## 1. Control priorities

Rank controls roughly in this order:

### Highest priority

- patch velocity across framework, kernel, and vendor components
- locked bootloader plus Verified Boot and rollback protection

Why:

- patch gaps and incomplete fix integration are repeatedly exploited
- strong boot integrity forces attackers back into harder runtime-only compromise

### High priority

- eliminate debug surfaces in production
- enforce SELinux correctness with no permissive domains
- audit privileged apps and permission allowlists to reduce footprint

Why:

- debug posture changes the attacker's starting position
- SELinux blocks entire classes of escalation when it is correct
- privileged apps are part of the trusted computing base and should be treated as high-risk surfaces

### Medium priority

- constrain and monitor Device Owner / DPC capabilities
- harden log and dump pipelines, especially OEM copies and bugreport paths

Why:

- management-plane abuse can be "worse than root"
- logs and copied diagnostics frequently lower exploit cost or leak sensitive state

## 2. Device Owner / DPC incident triage

This section assumes the concern is not ordinary malware, but attacker-controlled device management.

### Immediate containment

- isolate the device from enterprise networks while preserving state
- record visible managed-state indicators, restrictions, and admin prompts
- if the bootloader appears unlocked or warning-state, escalate severity because OS integrity is less trustworthy

### Evidence preservation

- snapshot Device Owner and profile owner identity
- capture policy posture, installed certificates, and app-install restrictions
- preserve crash, tombstone, and bugreport-related artifacts
- preserve enterprise logging, remote bugreport, and security-log state where available
- preserve OEM logs or copied diagnostics known to mirror privileged traces
- preserve Samsung denial-log collectors or zip outputs such as `SecurityLogAgent` activity around `samsung.intent.action.knox.DENIAL_NOTIFICATION` and `/data/misc/audit/audit.old`

### Rapid scoping questions

Ask before destructive remediation:

1. Is the Device Owner expected for this fleet or user?
2. Did management appear only after provisioning?
3. Did certificate delegation or certificate inventory change?
4. Did logging, bugreport, or package-management behavior change?
5. Does boot state or partition drift suggest a deeper persistence concern?

### Remediation

- if management is malicious, plan wipe-and-reprovision under controlled enrollment
- account for FRP and enterprise activation controls before wiping
- validate boot integrity and partition patch posture after reprovision

## 3. Defensive audit prompts

Use these prompts when the user wants a preventive review:

- Which privileged apps hold dangerous permissions they do not need?
- Which exported privileged components should be treated as externally reachable?
- Which OEM providers or Binder services could act as confused deputies?
- Are any vendor SELinux domains permissive or unusually broad?
- Are logs, dumpstate, bugreport, or OEM diagnostic copies weaker-protected than their sources?
- Do OEM collectors such as Samsung `SecurityLogAgent` mirror audit or denial data into app-managed zip flows that need tighter protection or monitoring?
- Does partition version drift keep vendor code behind the apparent security patch level?

## 4. Safe analysis patterns

### Detect unexpected Device Owner

```pseudo
known_good_dpc_packages = {"com.company.dpc", "com.company.mdm.agent"}

state = query_device_management_state(device)

if state.device_owner_package not in known_good_dpc_packages:
    alert("Unexpected Device Owner", severity="critical")

if state.new_device_owner_set_timestamp within last_7_days:
    alert("Recent Device Owner change", severity="high")

if state.enterprise_certificates_changed_recently:
    alert("Certificate posture changed", severity="high")
```

### Audit privileged-permission drift

```pseudo
allowlist = parse_all_privapp_permissions_xml(partitions=["system", "product", "vendor"])

for (pkg, perms) in allowlist:
    risky = intersection(perms, HIGH_RISK_PRIVILEGED_PERMISSIONS)
    if risky not empty and pkg not in approved_privileged_packages:
        flag(pkg, "Excess privileged permissions", risky)
```

## 5. Reporting language

Prefer:

- "high-risk control weakness"
- "management-plane exposure"
- "allowlist drift"
- "OEM logging hygiene issue"
- "boot-integrity concern"

Avoid:

- acting as if every defensive gap is already an exploit
- mixing confirmed compromise with preventative hardening guidance
