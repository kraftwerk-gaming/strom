package gaming.kraftwerk.strom.ipfs;

import java.io.IOException;

/**
 * A block did not hash to the CID that referenced it, or the CAR framing
 * broke. Distinct from a plain {@link IOException} because it means the
 * data is wrong rather than the transfer having failed: a caller should
 * try a different gateway, not retry the same one, and must never keep
 * the bytes.
 */
public class VerifyException extends IOException {
    public VerifyException(String message) {
        super(message);
    }
}
