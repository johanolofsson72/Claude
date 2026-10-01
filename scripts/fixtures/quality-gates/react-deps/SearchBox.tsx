import { useCallback, useState } from "react";

export function SearchBox({ onSearch }: { onSearch: (q: string) => void }) {
  const [query, setQuery] = useState("");
  const submit = useCallback(() => {
    onSearch(query.trim());
  }, [onSearch]);
  return (
    <form onSubmit={(e) => { e.preventDefault(); submit(); }}>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
    </form>
  );
}
