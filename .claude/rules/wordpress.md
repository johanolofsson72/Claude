---
globs: "**/*.php,**/wp-content/**"
---

# WordPress-regler

- Följ WordPress Coding Standards.
- Modifiera aldrig core-filer — använd child themes, hooks och filters.
- Använd `$wpdb->prepare()` för databasfrågor — aldrig rå SQL.
- Använd aldrig `eval()` eller `extract()`.
- Escapa all output med `esc_html()`, `esc_attr()`, `esc_url()`.
