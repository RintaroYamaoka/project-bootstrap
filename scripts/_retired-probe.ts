// TEMPORARY probe — exists only to prove the bootstrap-retired CI net actually fires on a
// real PR. It is removed in a follow-up commit on this same branch, and the PR's check
// history keeps the red -> green record. Do not merge this file.
export const probe = (i: { typeNo: number }) => i.typeNo;
