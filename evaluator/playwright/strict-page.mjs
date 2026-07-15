export function installStrictPageGuards(page) {
  const failures = [];
  page.on('console', (message) => {
    if (message.type() === 'error') failures.push(`console error: ${message.text()}`);
  });
  page.on('pageerror', (error) => failures.push(`page error: ${error.message}`));
  page.on('requestfailed', (request) => failures.push(`request failed: ${request.url()}`));
  return () => {
    if (failures.length) throw new Error(failures.join('\n'));
  };
}
