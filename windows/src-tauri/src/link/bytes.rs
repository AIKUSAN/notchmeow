// Hex and fixed-size byte helpers for the link. Hex is lower-case everywhere on the wire and in the stores (docs/LINK-CONTRACT.md, "Notes for ports"): upper case is not hex here.

pub const ID_LEN: usize = 16;

pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 15) as usize] as char);
    }
    out
}

fn nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        _ => None,
    }
}

/// The bytes of lower-case hex, or None for odd length, a capital or any other character.
pub fn unhex(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.len() % 2 != 0 {
        return None;
    }
    b.chunks(2).map(|p| Some(nibble(p[0])? << 4 | nibble(p[1])?)).collect()
}

/// A device id or transfer id: 16 bytes, 32 lower-case hex digits.
pub fn id16(s: &str) -> Option<[u8; ID_LEN]> {
    unhex(s)?.try_into().ok()
}

/// A nonce, a commitment or a public key: 32 bytes, 64 lower-case hex digits.
pub fn key32(s: &str) -> Option<[u8; 32]> {
    unhex(s)?.try_into().ok()
}

pub fn is_id_hex(s: &str) -> bool {
    id16(s).is_some()
}

pub fn is_key_hex(s: &str) -> bool {
    key32(s).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_round_trips_and_is_lower_case_only() {
        assert_eq!(hex(&[0, 1, 0xab, 0xff]), "0001abff");
        assert_eq!(unhex("0001abff"), Some(vec![0, 1, 0xab, 0xff]));
        assert_eq!(unhex("0001ABFF"), None, "capitals are not hex here");
        assert_eq!(unhex("abc"), None);
        assert_eq!(unhex("zz"), None);
        assert_eq!(unhex(""), Some(vec![]));
    }

    #[test]
    fn ids_and_keys_have_their_lengths() {
        assert!(is_id_hex(&"ab".repeat(16)));
        assert!(!is_id_hex(&"ab".repeat(15)));
        assert!(!is_id_hex(&"AB".repeat(16)));
        assert!(is_key_hex(&"cd".repeat(32)));
        assert!(!is_key_hex(&"cd".repeat(31)));
    }
}
