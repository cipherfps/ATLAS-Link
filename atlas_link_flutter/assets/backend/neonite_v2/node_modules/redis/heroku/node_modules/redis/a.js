let i = 1;

async function write(i) {
  try {
    await cluster.incr(i);
  } catch (err) {
    console.error(i, err);
  } finally {
    await write(i + 1);
  }
}
write(1)