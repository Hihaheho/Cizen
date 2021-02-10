# Used by "mix format"
locals_without_parens = [
  handle: 1,
  perform: 2,
  perform: 1,
  defeventbodyfilter: 2,
  defsagafilter: 2
]

[
  inputs: [".formatter.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
