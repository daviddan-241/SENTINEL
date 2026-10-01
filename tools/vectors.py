#!/usr/bin/env python3
"""
Reference vector generator for the SentinelWallet iOS app tests.

Everything here is implemented from the standards (BIP-39, BIP-32, BIP-44, BIP-49,
BIP-84, BIP-86, SLIP-10, EIP-55, BIP-173) in plain Python so the Swift implementation
can be checked against an independent source. It reads the same app/bip39.txt word list
that ships in the repo.

    python3 tools/vectors.py            # human-readable report
    python3 tools/vectors.py --json     # machine-readable vectors
"""
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import build  # noqa: E402

WORDS = build.load_bip39()
IDX = {w: i for i, w in enumerate(WORDS)}

# ----------------------------------------------------------------- secp256k1
P = 2**256 - 2**32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8


def inv(a, m=P):
    return pow(a, m - 2, m)


def add(p, q):
    if p is None:
        return q
    if q is None:
        return p
    if p[0] == q[0] and (p[1] + q[1]) % P == 0:
        return None
    if p == q:
        lam = (3 * p[0] * p[0]) * inv(2 * p[1]) % P
    else:
        lam = (q[1] - p[1]) * inv(q[0] - p[0]) % P
    x = (lam * lam - p[0] - q[0]) % P
    return (x, (lam * (p[0] - x) - p[1]) % P)


def mul(k, p=(Gx, Gy)):
    r = None
    while k:
        if k & 1:
            r = add(r, p)
        p = add(p, p)
        k >>= 1
    return r


def compressed(pt):
    x, y = pt
    return bytes([2 + (y & 1)]) + x.to_bytes(32, "big")


def xonly(pt):
    return pt[0].to_bytes(32, "big")


# ----------------------------------------------------------------- codecs
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58encode(b: bytes) -> str:
    n = int.from_bytes(b, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = B58[r] + out
    return "1" * (len(b) - len(b.lstrip(b"\0"))) + out


def b58check(payload: bytes) -> str:
    return b58encode(payload + hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4])


CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def bech32_polymod(values):
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= gen[i] if ((b >> i) & 1) else 0
    return chk


def hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def convertbits(data, frombits, tobits, pad=True):
    acc = bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for value in data:
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad and bits:
        ret.append((acc << (tobits - bits)) & maxv)
    return ret


def bech32_encode(hrp, data, spec="bech32"):
    const = 1 if spec == "bech32" else 0x2BC830A3
    values = hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ const
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(CHARSET[d] for d in data + checksum)


def segwit_address(hrp, ver, prog, spec="bech32"):
    return bech32_encode(hrp, [ver] + convertbits(list(prog), 8, 5), spec)


# ----------------------------------------------------------------- hashing helpers
def sha256(b):
    return hashlib.sha256(b).digest()


def hash160(b):
    from Crypto.Hash import RIPEMD160
    h = RIPEMD160.new()
    h.update(sha256(b))
    return h.digest()


def keccak256(b):
    from Crypto.Hash import keccak
    k = keccak.new(digest_bits=256)
    k.update(b)
    return k.digest()


def tagged_hash(tag, msg):
    t = sha256(tag.encode())
    return sha256(t + t + msg)


# ----------------------------------------------------------------- BIP-39 / BIP-32
def mnemonic_to_seed(mnemonic, passphrase=""):
    return hashlib.pbkdf2_hmac("sha512", mnemonic.encode(), ("mnemonic" + passphrase).encode(), 2048, 64)


def master(seed):
    import hmac as _hmac
    I = _hmac.new(b"Bitcoin seed", seed, hashlib.sha512).digest()   # BIP-32: HMAC-SHA512, not PBKDF2
    return int.from_bytes(I[:32], "big"), I[32:]


def ckd_priv_correct(k, c, i):
    import hmac as _hmac
    if i >= 2**31:
        data = b"\x00" + k.to_bytes(32, "big") + i.to_bytes(4, "big")
    else:
        data = compressed(mul(k)) + i.to_bytes(4, "big")
    I = _hmac.new(c, data, hashlib.sha512).digest()
    ki = (int.from_bytes(I[:32], "big") + k) % N
    return ki, I[32:]


def derive(path, key, chain):
    for part in path:
        key, chain = ckd_priv_correct(key, chain, part)
    return key, chain


def h(i):
    return i + 2**31


def xprv(key, chain, depth, parent_fp, index, prefix=b"\x04\x88\xad\xe4"):
    payload = prefix + bytes([depth]) + parent_fp + index.to_bytes(4, "big") + chain + b"\x00" + key.to_bytes(32, "big")
    return b58check(payload)


def xpub(point, chain, depth, parent_fp, index, prefix=b"\x04\x88\xb2\x1e"):
    payload = prefix + bytes([depth]) + parent_fp + index.to_bytes(4, "big") + chain + compressed(point)
    return b58check(payload)


def fingerprint(point):
    return hash160(compressed(point))[:4]


def eth_address(point):
    raw = keccak256(compressed(point)[1:] + point[1].to_bytes(32, "big"))[-20:]
    hx = raw.hex()
    out = "".join(c.upper() if c.isalpha() and int(keccak256(hx.encode()).hex()[i], 16) >= 8 else c
                  for i, c in enumerate(hx))
    return "0x" + out


def lift_x(x: int):
    """BIP-340 lift_x: the point with this x coordinate and an even y."""
    y2 = (pow(x, 3, P) + 7) % P
    y = pow(y2, (P + 1) // 4, P)
    assert (y * y) % P == y2, "x is not on the curve"
    return (x, y if y % 2 == 0 else P - y)


def taproot_address(point):
    """BIP-86: key-path-only P2TR. The internal key is used x-only, which means the
    even-y lift of that x coordinate — not the raw derived point — is what gets tweaked."""
    internal = lift_x(int.from_bytes(xonly(point), "big"))
    tweak = int.from_bytes(tagged_hash("TapTweak", xonly(point)), "big")
    out = add(internal, mul(tweak))
    return segwit_address("bc", 1, xonly(out), "bech32m")


def solana_address(seed32):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    pk = Ed25519PrivateKey.from_private_bytes(seed32)
    raw = pk.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return b58encode(raw), raw.hex()


MNEMONIC = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
TREZOR = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"


def collect():
    v = {}
    v["wordlist"] = {"first": WORDS[0], "last": WORDS[-1], "count": len(WORDS), "sha256": hashlib.sha256(
        "\n".join(WORDS).encode()).hexdigest(), "index_about": IDX["about"], "index_zoo": IDX["zoo"]}

    v["pbkdf2"] = [
        {"password": "password", "salt": "salt", "iterations": 1, "dklen": 64,
         "out": hashlib.pbkdf2_hmac("sha512", b"password", b"salt", 1, 64).hex()},
        {"password": "password", "salt": "salt", "iterations": 4096, "dklen": 64,
         "out": hashlib.pbkdf2_hmac("sha512", b"password", b"salt", 4096, 64).hex()},
        {"password": "mnemonic-pass", "salt": "mnemonic", "iterations": 2, "dklen": 32,
         "out": hashlib.pbkdf2_hmac("sha512", b"mnemonic-pass", b"mnemonic", 2, 32).hex()},
    ]

    seed_trezor = mnemonic_to_seed(MNEMONIC, "TREZOR")
    v["bip39_seed"] = {"mnemonic": MNEMONIC, "passphrase": "TREZOR", "seed": seed_trezor.hex()}
    seed_plain = mnemonic_to_seed(MNEMONIC, "")
    v["bip39_seed_no_passphrase"] = {"seed": seed_plain.hex()}

    v["bip39_validate"] = [
        {"phrase": MNEMONIC, "valid": True},
        {"phrase": "zoo " * 11 + "wrong", "valid": True},
        {"phrase": "zoo " * 12, "valid": False, "reason": "checksum"},
        {"phrase": "abandon " * 12, "valid": False, "reason": "checksum"},
        {"phrase": "abandon " * 11 + "zzz", "valid": False, "reason": "unknown word"},
        {"phrase": "abandon about", "valid": False, "reason": "word count"},
    ]

    # BIP-32 test vector 1
    seed1 = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    k, c = master(seed1)
    p = mul(k)
    v["bip32_vector1"] = {
        "seed": seed1.hex(),
        "master_xprv": xprv(k, c, 0, b"\x00" * 4, 0),
        "master_xpub": xpub(p, c, 0, b"\x00" * 4, 0),
        "pubkey_hex": compressed(p).hex(),
        "chain_code": c.hex(),
        "private_key": k.to_bytes(32, "big").hex(),
    }
    k1, c1 = derive([h(0)], k, c)
    p1 = mul(k1)
    v["bip32_vector1_child"] = {
        "path": "m/0'",
        "xprv": xprv(k1, c1, 1, fingerprint(p), h(0)),
        "xpub": xpub(p1, c1, 1, fingerprint(p), h(0)),
        "pubkey_hex": compressed(p1).hex(),
    }
    # deeper chains of test vector 1 (exercises hardened + normal derivation and xpub serialisation)
    deep = {
        "m/0'/1": ("xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ",
                   "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs"),
        "m/0'/1/2'": ("xpub6D4BDPcP2GT577Vvch3R8wDkScZWzQzMMUm3PWbmWvVJrZwQY4VUNgqFJPMM3No2dFDFGTsxxpG5uJh7n7epu4trkrX7x7DogT5Uv6fcLW5",
                      "xprv9z4pot5VBttmtdRTWfWQmoH1taj2axGVzFqSb8C9xaxKymcFzXBDptWmT7FwuEzG3ryjH4ktypQSAewRiNMjANTtpgP4mLTj34bhnZX7UiM"),
        "m/0'/1/2'/2": ("xpub6FHa3pjLCk84BayeJxFW2SP4XRrFd1JYnxeLeU8EqN3vDfZmbqBqaGJAyiLjTAwm6ZLRQUMv1ZACTj37sR62cfN7fe5JnJ7dh8zL4fiyLHV",
                        "xprvA2JDeKCSNNZky6uBCviVfJSKyQ1mDYahRjijr5idH2WwLsEd4Hsb2Tyh8RfQMuPh7f7RtyzTtdrbdqqsunu5Mm3wDvUAKRHSC34sJ7in334"),
        "m/0'/1/2'/2/1000000000": ("xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy",
                                   "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76"),
    }
    v["bip32_vector1_deep"] = []
    kd, cd, depth, parent_fp, child_index = k, c, 0, b"\x00" * 4, 0
    for step in ("0'", "1", "2'", "2", "1000000000"):
        child_index = h(int(step[:-1])) if step.endswith("'") else int(step)
        parent_fp = fingerprint(mul(kd))
        kd, cd = ckd_priv_correct(kd, cd, child_index)
        depth += 1
        path = "m/" + "/".join(["0'", "1", "2'", "2", "1000000000"][:depth])
        row = {"path": path,
               "xprv": xprv(kd, cd, depth, parent_fp, child_index),
               "xpub": xpub(mul(kd), cd, depth, parent_fp, child_index)}
        if path in deep:
            row["spec_xpub"], row["spec_xprv"] = deep[path]
            row["spec_match"] = (row["xpub"] == deep[path][0] and row["xprv"] == deep[path][1])
        v["bip32_vector1_deep"].append(row)

    # BIP-32 test vector 2 (longer chain, public derivation)
    seed2 = bytes.fromhex("fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542")
    k2, c2 = master(seed2)
    v["bip32_vector2"] = {
        "seed": seed2.hex()[:32] + "...",
        "master_xprv": xprv(k2, c2, 0, b"\x00" * 4, 0),
        "master_xpub": xpub(mul(k2), c2, 0, b"\x00" * 4, 0),
    }

    # BIP-44 / BIP-49 / BIP-84 / BIP-86 for the same mnemonic
    m, ch = master(seed_plain)
    mfp = fingerprint(mul(m))
    acct44, _ = derive([h(44), h(0), h(0)], m, ch)
    v["bip44_btc"] = {"path": "m/44'/0'/0'/0/0",
                      "address": b58check(b"\x00" + hash160(compressed(mul(derive([h(44), h(0), h(0), 0, 0], m, ch)[0]))))}
    acct49, c49 = derive([h(49), h(0), h(0)], m, ch)
    inner = hash160(compressed(mul(derive([0, 0], acct49, c49)[0])))
    v["bip49_btc"] = {"path": "m/49'/0'/0'/0/0",
                      "address": b58check(b"\x05" + hash160(b"\x00\x14" + inner))}
    acct84, c84 = derive([h(84), h(0), h(0)], m, ch)
    addr_pub = mul(derive([0, 0], acct84, c84)[0])
    v["bip84_btc"] = {
        "path": "m/84'/0'/0'/0/0",
        "address": segwit_address("bc", 0, hash160(compressed(addr_pub))),
        "account_xprv": xprv(acct84, c84, 3, xpub_fp := fingerprint(mul(derive([h(84), h(0)], m, ch)[0])), h(0),
                             b"\x04\xb2\x43\x0c"),
        "account_xpub": xpub(mul(acct84), c84, 3, xpub_fp, h(0), b"\x04\xb2\x47\x46"),
        "hash160": hash160(compressed(addr_pub)).hex(),
    }
    acct86, c86 = derive([h(86), h(0), h(0)], m, ch)
    v["bip86_btc"] = {"path": "m/86'/0'/0'/0/0",
                      "address": taproot_address(mul(derive([0, 0], acct86, c86)[0]))}
    account0_60, _ = derive([h(44), h(60), h(0)], m, ch)
    bip86_leaf = mul(derive([h(86), h(0), h(0), 0, 0], m, ch)[0])
    v["bip86_output_key"] = xonly(add(lift_x(int.from_bytes(xonly(bip86_leaf), "big")),
                                      mul(int.from_bytes(tagged_hash("TapTweak", xonly(bip86_leaf)), "big")))).hex()
    v["bip44_eth"] = {"path": "m/44'/60'/0'/0/0",
                      "address": eth_address(mul(derive([h(44), h(60), h(0), 0, 0], m, ch)[0]))}
    v["bip44_sol"] = {}
    sol_key, _ = derive([h(44), h(501), h(0), h(0)], m, ch)
    sol_addr, sol_hex = solana_address(sol_key.to_bytes(32, "big"))
    v["bip44_sol"] = {"path": "m/44'/501'/0'/0'", "address": sol_addr, "pubkey_hex": sol_hex}

    # address-level details for the ETH vector (used by the scan tests)
    eth_acct_xpub = None
    acct_pub = mul(account0_60)
    v["eth_account"] = {"path": "m/44'/60'/0'/0", "xpub": xpub(acct_pub, _, 3, mfp, h(0))}

    v["keccak256"] = [
        {"input": "", "out": keccak256(b"").hex()},
        {"input": "abc", "out": keccak256(b"abc").hex()},
        {"input": "The quick brown fox jumps over the lazy dog",
         "out": keccak256(b"The quick brown fox jumps over the lazy dog").hex()},
    ]
    v["ripemd160"] = [
        {"input": "", "out": __import__("Crypto.Hash.RIPEMD160", fromlist=["x"]).new().hexdigest()},
        {"input": "abc", "out": (lambda h: (h.update(b"abc"), h.hexdigest())[1])(
            __import__("Crypto.Hash.RIPEMD160", fromlist=["x"]).new())},
    ]
    v["sha256"] = [
        {"input": "", "out": hashlib.sha256(b"").hexdigest()},
        {"input": "abc", "out": hashlib.sha256(b"abc").hexdigest()},
    ]
    v["sha512"] = [
        {"input": "abc", "out": hashlib.sha512(b"abc").hexdigest()},
        {"input": "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "out": hashlib.sha512(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").hexdigest()},
    ]
    v["hmac_sha512"] = [
        {"key": "0b" * 20, "msg": "Hi There", "out": __import__("hmac").new(bytes.fromhex("0b" * 20), b"Hi There",
                                                                           hashlib.sha512).hexdigest()},
    ]
    b58_payload = hash160(compressed(mul(derive([h(44), h(0), h(0), 0, 0], m, ch)[0])))
    v["base58check"] = [{"version": "00", "payload": b58_payload.hex(), "out": v["bip44_btc"]["address"]}]
    v["bech32_valid"] = [
        "A12UEL5L", "a12uel5l", "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
        "1" + "1" + "q" * 82 + "c8247j",       # 90 chars: the longest legal bech32 string
        "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
        "?1ezyfcl",
    ]
    v["bech32_invalid"] = [
        " 1nwldj5",                            # HRP character out of range
        "\x7f1axkwrx",
        "\x801eym55h",
        "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx",
        "pzry9x0s0muk",                        # no separator
        "1pzry9x0s0muk",                       # empty HRP
        "x1b4n0q5v",                           # invalid data character
        "li1dgmt3",                            # checksum too short
        "de1lg7wt\xff",                        # invalid character in checksum
        "A1G7SGD8",                            # checksum of the uppercase HRP
        "10a06t8",                             # empty HRP
        "1qzzfhee",
    ]

    btc44_key = derive([h(44), h(0), h(0), 0, 0], m, ch)[0].to_bytes(32, "big")
    v["private_keys"] = {
        "wif_mainnet": b58check(b"\x80" + btc44_key),                       # uncompressed ("5…")
        "wif_compressed": b58check(b"\x80" + btc44_key + b"\x01"),         # compressed ("K…"/"L…")
        "hex": btc44_key.hex(),
    }
    return v


if __name__ == "__main__":
    data = collect()
    if "--json" in sys.argv:
        print(json.dumps(data, indent=2))
    else:
        print(json.dumps(data, indent=2)[:4000])
