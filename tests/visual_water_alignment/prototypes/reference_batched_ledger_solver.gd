extends "res://scripts/simulation/gpu_shallow_solver.gd"

## W07-only acknowledgement after the tide delta has been copied into a
## batch buffer. Accounting is performed later by the batch readback callback.
func acknowledge_tide_ledger_capture() -> bool:
	if not tide_ledger_pending or tide_ledger_requested or \
			tide_ledger_revision != state_revision:
		return false
	tide_ledger_pending = false
	tide_ledger_requested = false
	return true
