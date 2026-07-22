export async function sb(promise, res) {
  const { data, error } = await promise;
  if (error) {
    console.error(error);
    res.status(400).json({ error: error.message });
    return null;
  }
  return data;
}
