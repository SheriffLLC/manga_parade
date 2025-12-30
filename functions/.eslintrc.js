module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    // ✅ IMPORTANT: make paths resolve relative to THIS file
    tsconfigRootDir: __dirname,

    // ✅ Now these paths resolve correctly
    project: ["./tsconfig.json", "./tsconfig.dev.json"],

    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*",
    "/generated/**/*",
    ".eslintrc.js",
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  overrides: [
    {
      files: ["*.js"],
      parserOptions: {
        project: null,
      },
    },
  ],
  rules: {
    quotes: ["error", "double"],
    "import/no-unresolved": 0,
    indent: ["error", 2],
    "object-curly-spacing": ["error", "always"],
    "require-jsdoc": "off",
    "max-len": "off",
    "operator-linebreak": "off",
    "arrow-parens": "off",
    "quote-props": "off",
    "@typescript-eslint/no-explicit-any": "off",
  },
};
