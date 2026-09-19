const EXPECTED_PROJECT_NAME = 'mcpmaster';
const EXPECTED_ENVIRONMENT = 'production';
const TRUSTED = Object.freeze({
  ownerId: 'team_3yw1CN59ce4pj5SwyQGCAqN3',
  projectId: 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
  owner: 'mbanatao',
});

export function assertProductionVercelClaims(payload, audiences) {
  if (payload.environment !== EXPECTED_ENVIRONMENT) throw new Error('environment not allowed');
  if (payload.project !== EXPECTED_PROJECT_NAME) throw new Error('invalid project');
  if (payload.owner_id !== TRUSTED.ownerId || payload.project_id !== TRUSTED.projectId) {
    throw new Error('wrong project');
  }
  if (payload.owner !== TRUSTED.owner) throw new Error('invalid owner');
  const subject = `owner:${TRUSTED.owner}:project:${EXPECTED_PROJECT_NAME}:environment:${EXPECTED_ENVIRONMENT}`;
  if (payload.sub !== subject) throw new Error('invalid subject');
  if (!Array.isArray(audiences) || !audiences.includes(`https://vercel.com/${TRUSTED.owner}`)) {
    throw new Error('invalid audience');
  }
}
