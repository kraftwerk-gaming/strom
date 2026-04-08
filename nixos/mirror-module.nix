{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.strom-ipfs-mirror;
in
{
  options.services.strom-ipfs-mirror = {
    enable = lib.mkEnableOption "Mirror the strom IPFS content via IPNS";

    ipnsName = lib.mkOption {
      type = lib.types.str;
      default = "k51qzi5uqu5dgz69va1f3ha6b7hbdjgg3lz5qyq7kn4mx1vw6vxztc9445yr3a";
      description = ''
        IPNS name that the strom publisher writes to. The mirror periodically
        resolves it and recursively pins the resulting directory, so new
        content is picked up automatically.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "systemd OnCalendar expression for the periodic pin run.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.kubo = {
      enable = lib.mkDefault true;
      settings = {
        Experimental.FilestoreEnabled = lib.mkDefault true;
        Datastore.StorageMax = lib.mkDefault "100GB";
        Swarm = {
          ConnMgr = {
            LowWater = lib.mkDefault 100;
            HighWater = lib.mkDefault 400;
            GracePeriod = lib.mkDefault "20s";
          };
          Transports.Network.TCP = lib.mkDefault true;
          Transports.Network.QUIC = lib.mkDefault true;
          ResourceMgr = {
            Enabled = lib.mkDefault true;
            MaxMemory = lib.mkDefault "2GB";
          };
          RelayClient.Enabled = lib.mkDefault false;
          RelayService.Enabled = lib.mkDefault false;
        };
        # dhtclient: announces our provider records (so peers can find us
        # by CID) but does not serve DHT routing queries for others.
        Routing.Type = lib.mkDefault "dhtclient";
      };
    };

    networking.firewall.allowedTCPPorts = [ 4001 ];
    networking.firewall.allowedUDPPorts = [ 4001 ]; # QUIC

    systemd.services.strom-ipfs-pin = {
      description = "Pin /ipns/${cfg.ipnsName} (strom mirror)";
      after = [ "ipfs.service" ];
      wants = [ "ipfs.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "ipfs";
        Group = "ipfs";
      };
      script = ''
        ${config.services.kubo.package}/bin/ipfs pin add --progress --recursive /ipns/${cfg.ipnsName}
      '';
    };

    systemd.timers.strom-ipfs-pin = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };
}
