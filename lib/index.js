/**
 * ego-lite-windows-skill — one skill, shipped as a native DeepSeek Harness bundle.
 *
 * The skill lives in this package's `skills/ego-lite-windows/SKILL.md` and is
 * registered at apply time into dsh's `ctx.skills` registry through the same
 * filesystem provider that serves project/user skills, so it shows up in every
 * session catalog without a manual copy into `~/.dsh/skills`.
 *
 * Registration shape copied from dsh-embedded-workbench (0.9.8): `inject:
 * ['skills']` + a `registerProvider` call returning a `FileSystemSkillProvider`
 * with `includeDefaultRoots: false` and this package's own `skills/` directory
 * as the only custom root. The row mounts at the profile root, so every agent
 * preset sees the skill.
 *
 * Fail-safe by design: the host module is imported dynamically inside a
 * try/catch. A host that does not expose `@deepseek-ai/dsh-skill-filesystem`
 * leaves the provider unregistered instead of throwing at import time — a
 * throwing bundle entry takes the whole plugin tree, and the host boot, down
 * with it.
 *
 * @module ego-lite-windows-skill
 */
import { fileURLToPath } from 'node:url';

export const name = 'ego-lite-windows';

// The registry service is mounted by dsh-base before bundle rows like this one
// apply; `inject` makes that dependency explicit to the loader.
export const inject = ['skills'];

// `lib/index.js` sits one level below the package root, so `../skills` resolves
// to `<package>/skills` wherever the package was installed.
const SKILLS_DIR = fileURLToPath(new URL('../skills', import.meta.url));

let FileSystemSkillProvider;
try {
  ({ FileSystemSkillProvider } = await import('@deepseek-ai/dsh-skill-filesystem'));
} catch (err) {
  console.warn('[ego-lite-windows] dsh-skill-filesystem unavailable, skill not registered:', err?.message ?? err);
}

export function apply(ctx) {
  if (!FileSystemSkillProvider) return;
  try {
    ctx.skills.registerProvider((control) => {
      return new FileSystemSkillProvider(ctx, control, {
        providerName: 'ego-lite-windows',
        includeDefaultRoots: false,
        customSkillDirs: [SKILLS_DIR],
      });
    });
  } catch (err) {
    console.warn('[ego-lite-windows] skill registration failed:', err?.message ?? err);
  }
}
