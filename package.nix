{
  lib,
  fosrl-pangolin,
  makeWrapper,
  runCommand,
  nodejs,
}:

# Wrap upstream fosrl-pangolin to:
# 1. Provide runtime server/db/ json assets (names.json, ios_models.json, mac_models.json)
# 2. Fix the .next directory read-only permissions issue in the startup wrapper
# 3. Expose pangctl with nodejs in PATH
runCommand "pangolin-${fosrl-pangolin.version}-wrapped" {
  nativeBuildInputs = [ makeWrapper ];
  meta = fosrl-pangolin.meta // {
    description = "Tunneled reverse proxy server with identity and access control (wrapped with fixes for NixOS)";
  };
} ''
  mkdir -p $out/bin $out/share/pangolin/server/db

  # Link existing pangolin share directory
  ln -s ${fosrl-pangolin}/share/pangolin/* $out/share/pangolin/ 2>/dev/null || true
  rm -f $out/share/pangolin/server 2>/dev/null || true
  mkdir -p $out/share/pangolin/server/db

  # Copy and link db json assets where server.mjs expects them
  cp ${fosrl-pangolin}/share/pangolin/dist/names.json $out/share/pangolin/server/db/names.json
  cp ${fosrl-pangolin}/share/pangolin/dist/ios_models.json $out/share/pangolin/server/db/ios_models.json
  cp ${fosrl-pangolin}/share/pangolin/dist/mac_models.json $out/share/pangolin/server/db/mac_models.json

  # Create wrapped pangctl CLI
  makeWrapper ${nodejs}/bin/node $out/bin/pangctl \
    --add-flags "${fosrl-pangolin}/share/pangolin/dist/cli.mjs" \
    --prefix PATH : "${lib.makeBinPath [ nodejs ]}"

  # Create wrapped migrate-pangolin-database
  makeWrapper ${nodejs}/bin/node $out/bin/migrate-pangolin-database \
    --add-flags "${fosrl-pangolin}/share/pangolin/dist/migrations.mjs" \
    --prefix PATH : "${lib.makeBinPath [ nodejs ]}"

  # Create robust pangolin launcher wrapper
  cat << 'LAUNCHER' > $out/bin/pangolin
#!/usr/bin/env bash
set -e

DATA_DIR="''${PANGOLIN_DATA_DIR:-$(pwd)}"
cd "$DATA_DIR"

test -f public/.nix_skip_setup || {
  rm -f public
  ln -sf ${fosrl-pangolin}/share/pangolin/public .
}
test -f node_modules/.nix_skip_setup || {
  rm -f node_modules
  ln -sf ${fosrl-pangolin}/share/pangolin/node_modules .
}

if [ ! -f .next/.nix_skip_setup ]; then
  if [ ! -d .next ]; then
    cp -r --no-preserve=mode ${fosrl-pangolin}/share/pangolin/.next .
  fi
  chmod -R u+rwX .next 2>/dev/null || true
  touch .next/.nix_skip_setup 2>/dev/null || true
fi

mkdir -p server/db
ln -sf ${fosrl-pangolin}/share/pangolin/dist/*.json server/db/ 2>/dev/null || true

${nodejs}/bin/node ${fosrl-pangolin}/share/pangolin/dist/migrations.mjs

exec ${nodejs}/bin/node --enable-source-maps ${fosrl-pangolin}/share/pangolin/dist/server.mjs "$@"
LAUNCHER

  chmod +x $out/bin/pangolin
''
