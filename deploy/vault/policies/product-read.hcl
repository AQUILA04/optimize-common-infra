# Read secrets under secret/optimizesolux/*
path "secret/data/optimizesolux/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/optimizesolux/*" {
  capabilities = ["list", "read"]
}
