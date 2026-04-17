import NetworkExtension
import WireGuardKit

// Questo file deve stare nel target "NetworkExtension" in Xcode.
// wireguard_flutter lo usa automaticamente tramite il plugin.
// NON è necessario codice custom qui — il plugin gestisce tutto.

class PacketTunnelProvider: NEPacketTunnelProvider {
    // Gestito internamente da wireguard_flutter
}
