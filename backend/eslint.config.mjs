// @ts-check
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

/**
 * ESLint flat config for the Semuni backend.
 *
 * Intentionally non-type-aware (no `parserOptions.project`) so linting stays
 * fast and does not fail on files that are not part of a tsconfig. Type
 * correctness is enforced by `npm run build` (tsc) and the test suite.
 */
export default tseslint.config(
  {
    ignores: ['dist/**', 'coverage/**', 'node_modules/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  prettier,
  {
    files: ['**/*.ts'],
    rules: {
      // The codebase deliberately avoids `any`; keep it visible as a warning
      // rather than failing the build for the few boundary cases.
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrors: 'none',
          // Allow the "omit a field via rest" idiom, e.g.
          // `const { passwordHash, ...safeUser } = user;`
          ignoreRestSiblings: true,
        },
      ],
      // `try { ... } catch (_) {}` intentionally swallows non-critical errors.
      'no-empty': ['error', { allowEmptyCatch: true }],
    },
  },
  {
    // Tests build partial mocks and fixtures where `any` is the honest type.
    files: ['**/*.spec.ts', 'test/**/*.ts'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
  {
    // Ambient declaration files legitimately use `declare global`/namespaces.
    files: ['**/*.d.ts'],
    rules: {
      '@typescript-eslint/no-namespace': 'off',
    },
  },
);
