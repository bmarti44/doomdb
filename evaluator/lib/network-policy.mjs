export function validateEvaluatorCompose(text) {
  const failures = [];
  if (!/internal:\s*true/.test(text)) failures.push('evaluator network permits unapproved egress');
  if (/docker\.sock|privileged:\s*true|pid:\s*host/.test(text)) failures.push('evaluator has privileged host access');
  if (!/read_only:\s*true/.test(text)) failures.push('evaluator root is writable');
  if (!/\/held-back:ro/.test(text)) failures.push('held-back mount is not read-only');
  return failures;
}
