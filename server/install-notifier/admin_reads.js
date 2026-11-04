// Keep independent admin reads in flight without creating an unbounded number
// of KV subrequests. Results retain source order even when reads finish out of order.
export async function mapAdminReads(items, read, concurrency = 8) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await read(items[index], index);
    }
  }));
  return results;
}
