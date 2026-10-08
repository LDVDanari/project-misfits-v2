// Runs once when the server starts.
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const { startStoreSync } = await import('./lib/storeSync');
    startStoreSync();
  }
}
