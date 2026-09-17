export default function health(_request: unknown, response: any) {
  response.setHeader('Cache-Control', 'no-store');
  response.status(200).json({
    status: 'healthy',
    service: 'pandora-runtime',
    timestamp: new Date().toISOString(),
  });
}
