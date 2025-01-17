{ pkgs, CHaP }:
compiler-nix-name:
let
  inherit (pkgs) lib;
  inherit (pkgs.haskell-nix) haskellLib;

  # Build all the derivations that we care about for a package-version.
  #
  # Note that this is not-cheap in two ways:
  # 1. Each invocation of this function will incur some IFD to run the
  # cabal solver to create a build plan.
  # 2. Since each invocation of this has its own build plan, there is
  # little chance that derivations will actually be shared between 
  # invocations.
  build-chap-package = package-name: package-version:
    let
      package-id = "${package-name}-${package-version}";

      # Global config needed to build CHaP packages should go here. Obviously
      # this should be kept to an absolute minimum, since that means config
      # that every downstream project needs also.
      #
      # No need to set index-state:
      # - haskell.nix will automatically use the latest known one for hackage
      # - we want the very latest state for CHaP so it includes anything from
      #   e.g. a PR being tested
      project = (pkgs.haskell-nix.cabalProject' {
        inherit compiler-nix-name;

        name = package-id;
        src = ./empty;

        # Workaround until https://github.com/input-output-hk/haskell.nix/pull/1966
        # or similar is merged.
        sha256map = null;

        # Note that we do not set tests or benchmarks to True, so we won't
        # build them by default. This is the same as what happens on Hackage,
        # for example, and they can't be depended on by downstream packages
        # anyway.
        cabalProject = ''
          repository cardano-haskell-packages
            url: file:${CHaP}
            secure: True

          extra-packages: ${package-id}
        '';
      });

      # Wrapper around all package components
      #
      # The wrapper also provides shortcuts to quickly manipulate the cabal project.
      #
      # - addCabalProject adds arbitrary configuration to the project's cabalProjectLocal
      # - addConstraint uses addCabalProject to add a "constraints: " stanza
      # - allowNewer uses addCabalProject to add a "allow-newer: " stanza
      #
      # Note 1: We use cabalProjectLocal to be able to override cabalProject
      # Note 2: `cabalProjectLocal` ends up being prepended to the existing one
      # rather than appended. I think this is haskell.nix bug. If the project
      # has already a `cabalProjectLocal` this might not give the intended
      # result.
      aggregate = project:
        pkgs.releaseTools.aggregate
          {
            name = package-id;
            # Note that this does *not* include the derivations from 'checks' which
            # actually run tests: CHaP will not check that your tests pass (neither
            # does Hackage).
            constituents = haskellLib.getAllComponents project.hsPkgs.${package-name};
          } // {
          passthru = {
            # pass through the project for debugging purposes
            inherit project;
            # Shortcuts to manipulate the project, see above
            addCabalProject = cabalProjectLocal: aggregate (
              project.appendModule { inherit cabalProjectLocal; }
            );
            addConstraint = constraint: aggregate (
              project.appendModule { cabalProjectLocal = "constraints: ${constraint}"; }
            );
            allowNewer = allow-newer: aggregate (
              project.appendModule { cabalProjectLocal = "allow-newer: ${allow-newer}"; }
            );
          };
        };
    in
    aggregate project;
in
build-chap-package
