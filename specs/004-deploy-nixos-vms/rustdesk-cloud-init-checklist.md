# RustDesk Cloud-Init Automation - Requirements Quality Checklist

**Feature**: Automated RustDesk setup via cloud-init for NixOS VMs with direct IP access via Tailscale

**Purpose**: Validate requirements quality (completeness, clarity, consistency, measurability) before implementation

---

## 1. Systemd Service Creation Requirements

### 1.1 Service File Specification
- [ ] **CRITICAL GAP**: Is systemd service file creation documented in cloud-init runcmd? [Completeness]
  - **Current State**: Spec FR-RUST-006 requires `/etc/systemd/system/rustdesk.service` but cloud-init implementation (nixos-vm-cloudinit-secrets-chart.ts:154) only attempts restart, doesn't create service
  - **Expected**: Cloud-init should create service file before attempting restart
  - **Reference**: Spec FR-RUST-006 through FR-RUST-011

- [ ] **Service File Content**: Are all required systemd directives specified? [Completeness, Spec FR-RUST-007 to FR-RUST-011]
  - Type=simple
  - ExecStart=/run/current-system/sw/bin/rustdesk --service
  - After=network.target
  - Restart=on-failure
  - RestartSec=5
  - WantedBy=multi-user.target
  - Environment="LIBGL_ALWAYS_SOFTWARE=1"

- [ ] **Service Enablement**: Is `systemctl enable rustdesk` specified in cloud-init? [Completeness]
  - **Current State**: Not documented in cloud-init implementation
  - **Expected**: Service must be enabled to start on boot

### 1.2 Service Startup Sequence
- [ ] **Automation Flow**: Is the complete startup sequence documented? [Clarity]
  - Expected sequence:
    1. Cloud-init creates `/etc/systemd/system/rustdesk.service`
    2. Cloud-init creates `/root/.config/rustdesk/RustDesk2.toml`
    3. Cloud-init runs `systemctl daemon-reload`
    4. Cloud-init runs `systemctl enable rustdesk`
    5. Cloud-init runs `systemctl start rustdesk`
  - **Current State**: Only steps 2 and partial 5 (restart attempt) are implemented

---

## 2. Headless Mode Configuration

### 2.1 Headless Mode Requirements
- [ ] **Headless Mode Flag**: Is `allow-linux-headless = "Y"` specified in RustDesk2.toml? [Completeness, Spec FR-RUST-012]
  - **Current State**: YES - implemented in nixos-vm-cloudinit-secrets-chart.ts:148
  - **Reference**: Spec FR-RUST-012, Implementation line 148

- [ ] **GL Fallback**: Is `LIBGL_ALWAYS_SOFTWARE=1` environment variable specified? [Completeness, Spec NFR-RUST-009]
  - **Current State**: Should be in systemd service Environment directive
  - **Reference**: Spec NFR-RUST-009 (GL error handling)

- [ ] **Binary Compatibility**: Is RustDesk version/headless support verified? [Completeness]
  - **Expected**: Document RustDesk version that supports headless mode
  - **Current State**: Not specified in requirements

### 2.2 Headless vs Full Desktop
- [ ] **Service Name Consistency**: Is service name consistent (rustdesk vs rustdesk-headless)? [Consistency]
  - **Current State**: Cloud-init attempts restart of both `rustdesk` and `rustdesk-headless` (line 154)
  - **Expected**: Choose one service name and use consistently
  - **Recommendation**: Use `rustdesk` (single service with headless flag in config)

---

## 3. Direct IP Access via Tailscale

### 3.1 Network Access Requirements
- [ ] **Direct Access Port**: Is port 21116 specified for direct access? [Measurability, Spec FR-RUST-014]
  - **Current State**: YES - `direct-access-port = "21116"` in config (line 150)
  - **Reference**: Spec FR-RUST-014, Implementation line 150

- [ ] **Direct Server Mode**: Is `direct-server = "Y"` specified? [Completeness, Spec FR-RUST-013]
  - **Current State**: YES - implemented in nixos-vm-cloudinit-secrets-chart.ts:149
  - **Reference**: Spec FR-RUST-013, Implementation line 149

- [ ] **Tailscale Network Access**: Is VM pod IP accessible via Tailscale subnet routes? [Completeness]
  - **Expected**: Tailscale subnet router advertises 10.244.0.0/16 routes
  - **Current State**: Documented in CLAUDE.md but not in RustDesk spec
  - **Access Method**: Connect RustDesk client to VM pod IP (e.g., 10.244.0.180:21116)

### 3.2 Firewall and Network Policy
- [ ] **Port Exposure**: Is port 21116 exposed in KubeVirt VM network? [Completeness]
  - **Expected**: VM definition should expose port 21116
  - **Current State**: Not specified in cloud-init requirements

- [ ] **Kubernetes Service**: Is a Service resource required for RustDesk access? [Clarity]
  - **Expected**: Document whether NodePort/ClusterIP service is needed
  - **Current State**: Not specified (direct pod IP access via Tailscale may be sufficient)

---

## 4. Permanent Password Configuration

### 4.1 Password Source
- [ ] **Azure Key Vault Integration**: Is permanent password sourced from Azure Key Vault? [Completeness, Spec FR-RUST-015]
  - **Current State**: YES - `{{ .rustdesk_password }}` template variable (line 147)
  - **Reference**: Spec FR-RUST-015, ExternalSecret pulls from RUSTDESK-PASSWORD key

- [ ] **Password Placeholder**: Is template variable `{{ .rustdesk_password }}` used consistently? [Consistency]
  - **Current State**: YES - used in config file (line 147) and info file (line 157)
  - **Reference**: Implementation lines 147, 157

### 4.2 Password Application
- [ ] **Config File Update**: Is permanent-password written to RustDesk2.toml? [Completeness, Spec FR-RUST-016]
  - **Current State**: YES - implemented in nixos-vm-cloudinit-secrets-chart.ts:138-147
  - **Reference**: Spec FR-RUST-016, Implementation lines 138-147

- [ ] **Password Visibility**: Is password saved to /root/rustdesk-info.txt with restrictive permissions? [Security, Spec FR-RUST-018]
  - **Current State**: YES - `chmod 600 /root/rustdesk-info.txt` (line 158)
  - **Reference**: Spec FR-RUST-018, Implementation line 158

---

## 5. Cloud-Init Script Reliability

### 5.1 Error Handling
- [ ] **Service Restart Error Handling**: Is service restart failure handled gracefully? [Reliability]
  - **Current State**: YES - `|| true` at end of restart command (line 154)
  - **Issue**: This masks the service creation gap (restart fails silently because service doesn't exist)
  - **Expected**: Fail loudly if service creation fails, succeed silently only if service already running

- [ ] **PATH Configuration**: Is NixOS system PATH set correctly? [Completeness, Spec NFR-RUST-015]
  - **Current State**: YES - `export PATH="${nixosSystemPath}"` (line 133)
  - **Reference**: Spec NFR-RUST-015, Implementation line 133

### 5.2 Idempotency
- [ ] **Config File Update vs Create**: Does cloud-init handle existing RustDesk2.toml? [Reliability]
  - **Current State**: YES - checks if file exists and updates password line (lines 136-147)
  - **Reference**: Implementation lines 136-147

- [ ] **Service Restart vs Start**: Should cloud-init use `systemctl restart` or `systemctl start`? [Clarity]
  - **Current State**: Uses `systemctl restart` (line 154)
  - **Issue**: Restart fails if service doesn't exist (should be `start` after service creation)

---

## 6. Automation Completeness

### 6.1 Full Automation Validation
- [ ] **CRITICAL**: Can VM boot and RustDesk start without manual intervention? [Completeness, Measurability]
  - **Current State**: NO - service file missing prevents automatic startup
  - **Expected**: Cloud-init should complete all setup, VM accessible via RustDesk immediately after boot
  - **Test Criteria**:
    - VM boots successfully
    - `systemctl status rustdesk` shows active (running)
    - RustDesk client connects to VM_POD_IP:21116 using permanent password
    - Connection succeeds within 60 seconds of VM running

- [ ] **No Manual Configuration**: Are all configuration steps automated in cloud-init? [Completeness]
  - **Current State**: NO - systemd service file creation is missing
  - **Gap**: Manual creation of `/etc/systemd/system/rustdesk.service` required

---

## 7. Requirements Documentation Quality

### 7.1 Completeness
- [ ] **Systemd Service Creation**: Is service file creation workflow fully documented? [Completeness]
  - **Status**: INCOMPLETE - spec has requirements but cloud-init implementation missing

- [ ] **Headless Mode Dependencies**: Are RustDesk version/binary requirements specified? [Completeness]
  - **Status**: INCOMPLETE - no version requirement documented

### 7.2 Clarity
- [ ] **Access Instructions**: Is connection procedure clearly documented? [Clarity]
  - **Expected**: "Connect RustDesk client to <VM_POD_IP>:21116 using password from Azure Key Vault"
  - **Current State**: Documented in CLAUDE.md but not in formal spec

### 7.3 Consistency
- [ ] **Service Name**: Is service name used consistently (rustdesk vs rustdesk-headless)? [Consistency]
  - **Issue**: Cloud-init tries both names (line 154)
  - **Expected**: Use single service name throughout

### 7.4 Measurability
- [ ] **Success Criteria**: Are acceptance criteria quantified? [Measurability]
  - **Expected**: "RustDesk connection succeeds within 60 seconds of VM running"
  - **Current State**: Not quantified in spec

---

## 8. Implementation Gap Summary

### Critical Gaps (Must Fix):
1. **Systemd service file creation** - cloud-init does not create `/etc/systemd/system/rustdesk.service`
2. **Service enablement** - cloud-init does not run `systemctl enable rustdesk`
3. **Daemon reload** - cloud-init does not run `systemctl daemon-reload` after creating service file

### Minor Gaps (Should Fix):
1. **Service name consistency** - choose rustdesk or rustdesk-headless, not both
2. **Error handling** - fail loudly if service creation fails, not silently
3. **Version requirements** - document RustDesk version that supports headless mode
4. **Kubernetes Service resource** - document whether needed for RustDesk access

### Documentation Gaps (Nice to Have):
1. **Connection instructions** - add to formal spec, not just CLAUDE.md
2. **Success criteria** - quantify "connection succeeds within X seconds"
3. **Troubleshooting guide** - document common failure modes and fixes

---

## 9. Recommended Implementation Order

1. **Add systemd service file creation to cloud-init** (Critical)
   - Create `/etc/systemd/system/rustdesk.service` with all required directives
   - Run `systemctl daemon-reload`
   - Run `systemctl enable rustdesk`
   - Run `systemctl start rustdesk` (not restart)

2. **Update error handling** (Critical)
   - Check service creation success before starting
   - Log failures to /var/log/cloud-init-output.log

3. **Verify headless mode works** (High Priority)
   - Test RustDesk connection via Tailscale to VM pod IP:21116
   - Verify permanent password authentication
   - Confirm no GL errors in logs

4. **Update documentation** (Medium Priority)
   - Add connection instructions to formal spec
   - Document troubleshooting steps
   - Quantify success criteria

---

## Checklist Usage

**Purpose**: Validate requirements quality before implementation

**How to Use**:
1. Review each checklist item
2. Mark items that reveal gaps, inconsistencies, or unclear requirements
3. Prioritize gaps (Critical > High > Medium > Low)
4. Implement fixes for critical gaps first
5. Re-validate after implementation

**Next Steps** (per user request: "compact and implement the checklist"):
1. Review this checklist
2. Identify critical gaps (systemd service creation)
3. Implement fixes in `nixos-vm-cloudinit-secrets-chart.ts`
4. Test RustDesk connection via Tailscale
5. Update documentation with verified connection instructions
