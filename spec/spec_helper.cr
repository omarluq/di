require "spec"
require "../src/di"
require "./support/*"
require "./shared/*"
include TestHelpers

# Auto-reset Di container between specs to prevent state leakage.
Spec.after_each do
  Di.reset!
end
