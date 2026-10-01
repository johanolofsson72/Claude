# Quality-gate corpus (spec 020)

One directory per hook: two files with a seeded defect and two clean files, named so the
hook's own trigger fires. `expect.tsv` says which is which and, for a seeded defect, the word a true
flag names. `bash scripts/quality-gate-bench.sh` scores every hook against it and rewrites
`scripts/quality-gates.tsv`. These files are fixtures: they are never built or run.
