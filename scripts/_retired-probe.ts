// TEMPORARY probe — exists only to prove the bootstrap-retired CI net actually fires on a
// real PR. It is removed in a follow-up commit on this same branch, and the PR's check
// history keeps the red -> green record. Do not merge this file.
//
// The probe identifier is deliberately unique to this file. Using the real incident's name
// (typeNo) turned the CI red for the wrong reason: this plugin's own source comments and test
// fixtures legitimately spell that name out, so the red was not attributable to the probe.
// That is itself a finding — the exemption list covers docs/md, NOT code comments.
export const probe = (i: { probeRetiredName: number }) => i.probeRetiredName;
