#!/usr/bin/env python3
"""Writes the JSON fixtures of the link contract (standard library only).

The expected answers are written out here by hand (or, for the Noise vectors and the pairing codes,
pasted once from the reference and then frozen) and never computed by reference.py, so the fixtures and
the reference check each other. Run it after an intended change to a rule:
    python3 tests/fixtures/link/build_cases.py          # rewrite the fixtures
    python3 tests/fixtures/link/build_cases.py --check  # exit 1 if they drifted from this script
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MISSING = object()  # a key that is absent from the JSON; None is written as null


def noise_vectors():
    """The Noise vectors: pasted once from the reference (with keys that are plain byte patterns), cross-checked with CryptoKit, and frozen here."""
    vectors = [
            {
                "id": "xx-link",
                "name": "XX with the link prologue, a commitment, two hellos with their nonces and four transport messages",
                "source": "generated",
                "protocol_name": "Noise_XX_25519_ChaChaPoly_SHA256",
                "init_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "init_static": "1111111111111111111111111111111111111111111111111111111111111111",
                "init_ephemeral": "2222222222222222222222222222222222222222222222222222222222222222",
                "resp_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "resp_static": "3333333333333333333333333333333333333333333333333333333333333333",
                "resp_ephemeral": "4444444444444444444444444444444444444444444444444444444444444444",
                "handshake_hash": "81a05cf7b6a9de07e94817419e10face690a036f2333659f36b40f0170dcc5a6",
                "messages": [
                    {
                        "payload": "2d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0",
                        "ciphertext": "0faa684ed28867b97f4a6a2dee5df8ce974e76b7018e3f22a1c4cf2678570f202d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0"
                    },
                    {
                        "payload": "01b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b10b7465737420646576696365",
                        "ciphertext": "ff2ee45601ec1b67310c7790404585ae697331eee1c1f8cf2419731c1fff3e6b5cda1c2d8029877d73fad62823946ccd0c5da35c129100f43d33a59cf19ea8fc1239fa0de91ca151cc1c1091a1d97365fc2080a06e24a0646a518d620aad6f50cdd1fefbcd0924be407ba42981a6083981cbd98f806ece9d90907bd064b526da14556d1cca11f186638f200c9a6bfd7b19d9ddff3acb900cea084fb4f0"
                    },
                    {
                        "payload": "01a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a10b7465737420646576696365",
                        "ciphertext": "f4e4988e97bdcbf0f799d02dd2242624bda72d200e97e322c4f723213896a31e395e1ab82bc432b763e3ba34b0728004faacf16ffc2f8cac359b5d6e09c3da268f47bf8ab9f19e6e1c04332f75a84856897cdb761f431c14078167debf397674d5bd7725336d547ad1dfde09311ca430b91c7d3340df35ba40625aeb31"
                    },
                    {
                        "payload": "",
                        "ciphertext": "7d22cd25844b12db5ad4038aa7bbaaea"
                    },
                    {
                        "payload": "6e6f7463686d656f77",
                        "ciphertext": "4929ccc3e916b4f8335ae4053d9f642f970460babf2d7c2f4a"
                    },
                    {
                        "payload": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60616263",
                        "ciphertext": "0c31f02a30ca78d907f0921309ccc813e7c34d24eaa55c3fcfe00b0e0d6282f17a334e59f71c60218425fdd575550f3b45593160f265d701f552a5571cfa8d52df431801f0dc1ce69f20bf843a9fb18c8b6e5679b11072a44cc43042a84d0452e98f1c311dff26600930797e5a49d2d9cdc8abc6"
                    },
                    {
                        "payload": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                        "ciphertext": "743ae703840f50025e3f74db5722cd3fc6b010463d8e1a2d13a5bc0dbdbdd42654bb3c5e065710d0a7751671b5ed309aec"
                    }
                ]
            },
            {
                "id": "xx-empty",
                "name": "XX with an empty prologue and empty payloads",
                "source": "generated",
                "protocol_name": "Noise_XX_25519_ChaChaPoly_SHA256",
                "init_prologue": "",
                "init_static": "0101010101010101010101010101010101010101010101010101010101010101",
                "init_ephemeral": "0202020202020202020202020202020202020202020202020202020202020202",
                "resp_prologue": "",
                "resp_static": "0303030303030303030303030303030303030303030303030303030303030303",
                "resp_ephemeral": "0404040404040404040404040404040404040404040404040404040404040404",
                "handshake_hash": "21acd1864c5e1ad3a31a5878ece019767878774200e5cadca6199731b2cf009b",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "ce8d3ad1ccb633ec7b70c17814a5c76ecd029685050d344745ba05870e587d59"
                    },
                    {
                        "payload": "",
                        "ciphertext": "ac01b2209e86354fb853237b5de0f4fab13c7fcbf433a61c019369617fecf10bb719b14d19eaf5ca91c89748c5ce8668e6864f05ee2367682b3e0c2fd086f0b4f64162733f3fe548251c518fe8c03cce5fc0bcf3f8dea9b003f930ab273300e0"
                    },
                    {
                        "payload": "",
                        "ciphertext": "539a5cf3ae8a0a9134b32bfa775a1522db3558a1351ed4101989b8b88aa6a6f020da6d184283343a1d38fad23b3af58bc614f9b447f9aeb2a583c37b06bc4265"
                    },
                    {
                        "payload": "",
                        "ciphertext": "dee08d4fdeb182971f361ce87d782231"
                    },
                    {
                        "payload": "",
                        "ciphertext": "53231e10e978b5f74fb13e6b407c7c55"
                    },
                    {
                        "payload": "78",
                        "ciphertext": "a45b0c2d950faf9d96554a945645c3a566"
                    },
                    {
                        "payload": "",
                        "ciphertext": "a522f2484848db3857d90226afa01077"
                    }
                ]
            },
            {
                "id": "kk-link",
                "name": "KK with the link prologue and five transport messages",
                "source": "generated",
                "protocol_name": "Noise_KK_25519_ChaChaPoly_SHA256",
                "init_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "init_static": "5555555555555555555555555555555555555555555555555555555555555555",
                "init_ephemeral": "6666666666666666666666666666666666666666666666666666666666666666",
                "init_remote_static": "1cf579aba45a10ba1d1ef06d91fca2aa9ed0a1150515653155405d0b18cb9a67",
                "resp_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "resp_static": "7777777777777777777777777777777777777777777777777777777777777777",
                "resp_ephemeral": "8888888888888888888888888888888888888888888888888888888888888888",
                "resp_remote_static": "38ab664bd86f77d7e66bdd9ae0792913a94fd8b33a1260027e4b46c1f4884c67",
                "handshake_hash": "e0a44e29f4dbbcb45ec7d43bb61df80a99866163a508c623677aa0a832e77637",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "219e4d800da968d2a5fcb009c784f4746c7138edb9ee4844b739e830b05cf424f644bdd9ac7fdc94322a0e4cc55ec904"
                    },
                    {
                        "payload": "",
                        "ciphertext": "30d3c865a48fceb3d6118577cf2e5f228d6ff69866264757785b253cb7a4806ab81c01883b4690bb8a5bcc39ab680394"
                    },
                    {
                        "payload": "6f66666572",
                        "ciphertext": "f4e9efe22fbfd63b48aa20d57058608e7b2500cd9d"
                    },
                    {
                        "payload": "616363657074",
                        "ciphertext": "71cdeb478c8a786f907d47e080f87150592cb7c96fdc"
                    },
                    {
                        "payload": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7",
                        "ciphertext": "afb896d42c92a6042ec5962365edaebff963073551d898cd0ed1908c3eb8502091de4294df4ef31bbb3d48b4e4de78acef481e4e1f39943de24427decea114aede0eaa5bff917ac5e1611880581159abfe0915efe7297d8780f5eb944552831acb401a922493688b610a7733cc8ecd5ee340457709719e0b4d31d43c74fdbee18bdfcc6cd3769ace1e1453e2d028d76de1496800d5919dbe821bd48aa4a6536f1e6b6ca363a59cd7f03d0bfa18204d40e6444bd0b94e7cf1840d2c249d228deb87d74b10d20a3d9164e60e6aab6d7a58a4da68c65d3d90f5"
                    },
                    {
                        "payload": "",
                        "ciphertext": "4cdc64f814c85b9e976298155fb754ca"
                    },
                    {
                        "payload": "646f6e65",
                        "ciphertext": "a9b7b87c3fa791f62c9914d5380cdc3750d07c93"
                    }
                ]
            },
            {
                "id": "kk-empty",
                "name": "KK with an empty prologue and empty payloads",
                "source": "generated",
                "protocol_name": "Noise_KK_25519_ChaChaPoly_SHA256",
                "init_prologue": "",
                "init_static": "0505050505050505050505050505050505050505050505050505050505050505",
                "init_ephemeral": "0606060606060606060606060606060606060606060606060606060606060606",
                "init_remote_static": "13be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d",
                "resp_prologue": "",
                "resp_static": "0707070707070707070707070707070707070707070707070707070707070707",
                "resp_ephemeral": "0808080808080808080808080808080808080808080808080808080808080808",
                "resp_remote_static": "50a61409b1ddd0325e9b16b700e719e9772c07000b1bd7786e907c653d20495d",
                "handshake_hash": "cd0cb6c55bc49047e3ac8dc35653f2631aaf7cd2bcb66094c5489ce529893be1",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "f5b2d6e60f9477e310c2982daaa6c9136c108a1777c5947e448fa37d68174557710cd6754ad99ee323ac1a1408d8a293"
                    },
                    {
                        "payload": "",
                        "ciphertext": "31d4ab6aceec961137917037936e60716fac573afe94d9da84a8020448dfc1124b3eca92daf7135fa8aa45696abd4318"
                    },
                    {
                        "payload": "",
                        "ciphertext": "1bfa39ea261f6dd93180b68ec07492b3"
                    },
                    {
                        "payload": "",
                        "ciphertext": "a873107e477aa47cd1b96409751d7240"
                    },
                    {
                        "payload": "79",
                        "ciphertext": "eff99e4efa192f4c45eb376602923fcff8"
                    }
                ]
            }
        ]
    reject = []

    def bad(name, vector, failsAt, kind, **more):
        reject.append({"name": name, "vector": vector, "kind": kind, **more, "failsAt": failsAt})

    # XX: message 0 is the initiator's ephemeral key, 1 the responder's reply with its static key, 2 the initiator's static key, 3 and on are transport messages.
    bad("xx: a flipped bit in the initiator's ephemeral key spoils the reply, which the initiator then cannot open", "xx-link", 1, "flip", message=0, offset=0)
    bad("xx: a flipped bit in the commitment, the payload of the first message, spoils the reply", "xx-link", 1, "flip", message=0, offset=40)
    bad("xx: a flipped bit in the responder's encrypted static key", "xx-link", 1, "flip", message=1, offset=40)
    bad("xx: a flipped bit in the last byte of the reply, which is its tag", "xx-link", 1, "flip", message=1, offset=156)
    bad("xx: a flipped bit in the initiator's encrypted static key", "xx-link", 2, "flip", message=2, offset=0)
    bad("xx: the reply one byte short", "xx-link", 1, "truncate", message=1, by=1)
    bad("xx: the first message cut to 31 bytes, too short to hold a key", "xx-link", 0, "truncate", message=0, by=33)
    bad("xx: a flipped bit in the first transport message", "xx-link", 3, "flip", message=3, offset=0)
    bad("xx: the first transport message delivered twice", "xx-link", 3, "replay", message=3)
    bad("xx: a transport message arrives without the one before it", "xx-link", 5, "skip", message=5)
    bad("xx: an ephemeral key that is the zero point (a low-order point)", "xx-link", 1, "low-order", message=0, because="low-order point")
    bad("xx: the initiator has another prologue (another protocol version)", "xx-link", 1, "prologue", prologue=b"notchmeow-link/2".hex())
    # KK: message 0 is the initiator's ephemeral key, 1 the reply, 2 and on are transport messages.
    bad("kk: a flipped bit in the initiator's ephemeral key", "kk-link", 0, "flip", message=0, offset=0)
    bad("kk: a flipped bit in the last byte of the reply", "kk-link", 1, "flip", message=1, offset=47)
    bad("kk: the responder holds another key for the initiator", "kk-link", 0, "static", respRemoteStatic=bytes([9] * 32).hex())
    bad("kk: the first transport message delivered twice", "kk-link", 2, "replay", message=2)
    bad("kk: a transport message arrives without the one before it", "kk-link", 4, "skip", message=4)
    bad("kk: an ephemeral key that is the zero point", "kk-link", 0, "low-order", message=0, because="low-order point")
    bad("kk: the initiator has another prologue", "kk-link", 0, "prologue", prologue=b"notchmeow-link/2".hex())
    bad("kk: a flipped bit in a transport message", "kk-link", 3, "flip", message=3, offset=5)
    note = ("Noise_XX_25519_ChaChaPoly_SHA256 pairs two machines and Noise_KK_25519_ChaChaPoly_SHA256 carries a transfer. Each vector is in the format of the published "
            "cacophony / snow vectors: the keys, the messages alternate initiator first (transport messages too), and handshake_hash is the hash after the last handshake message. "
            "source says where a vector came from. rejectCases damage what is delivered: see noise_run in reference.py for the kinds. failsAt is the index of the message at which a side must refuse. because (the zero-point cases only) is the reference's own reason: a port checks that the zero key is refused as such. "
            "The keys in these vectors are plain byte patterns made for tests, never real keys.")
    return {"version": 1, "note": note, "prologue": '6e6f7463686d656f772d6c696e6b2f31', "vectors": vectors, "rejectCases": reject}
def pairing_cases():
    """The commitments and the codes are pasted once from the reference and frozen here; one commitment and one code were also worked out with `openssl dgst -sha256`, which agrees."""
    N, M, SI, SR = "a1" * 32, "b1" * 32, "c1" * 32, "c2" * 32     # the initiator's nonce, the responder's nonce, their static keys: plain patterns made for tests
    commits = [
        {"name": "a nonce and a key", "nonce": N, "static": SI, "commit": "4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d"},
        {"name": "the same nonce under another key: another commitment", "nonce": N, "static": SR, "commit": "63cdd5031f2d4bdd441b126924ba504fac75a6232f81ad2870b49ab0cfc02934"},
        {"name": "all zeros", "nonce": "00" * 32, "static": "00" * 32, "commit": "8d8b1a74a8c0b374e1cecd4579d33ed784470385b72a280f893c75b2ee274a2b"},
        {"name": "all ones", "nonce": "ff" * 32, "static": "ff" * 32, "commit": "e696a5dc70a722bfd46d12c64d1ee4787888862e22bcdd8ada9ef66d96c6d124"},
        {"name": "a counting nonce", "nonce": bytes(range(32)).hex(), "static": SI, "commit": "66507b3e4a69a747a2a52b3cedd4feabb6fd66836adc7d97cae47b24da3f5850"},
    ]
    codes = [
        {"name": "a pairing", "nonceI": N, "nonceR": M, "staticI": SI, "staticR": SR, "code": "479411"},
        {"name": "the two nonces swapped", "nonceI": M, "nonceR": N, "staticI": SI, "staticR": SR, "code": "080624"},
        {"name": "the two static keys swapped", "nonceI": N, "nonceR": M, "staticI": SR, "staticR": SI, "code": "585340"},
        {"name": "all zeros", "nonceI": "00" * 32, "nonceR": "00" * 32, "staticI": "00" * 32, "staticR": "00" * 32, "code": "608564"},
        {"name": "all ones", "nonceI": "ff" * 32, "nonceR": "ff" * 32, "staticI": "ff" * 32, "staticR": "ff" * 32, "code": "848961"},
        {"name": "a counting initiator nonce", "nonceI": bytes(range(32)).hex(), "nonceR": M, "staticI": SI, "staticR": SR, "code": "803937"},
        {"name": "a code that starts with three zeros keeps them", "nonceI": "165b6120ed15c5315aa509306b30f1984630df0155dd087af96ef93660272454", "nonceR": M, "staticI": SI, "staticR": SR, "code": "000973"},
    ]
    bad = [("a nonce of 31 bytes", "a1" * 31), ("a nonce of 33 bytes", "a1" * 33), ("an empty nonce", ""), ("a nonce that is text", "zz"), ("no nonce", None)]
    invalid = [{"name": n, "field": "nonceI", "value": v} for n, v in bad] + [{"name": "a static key of 31 bytes", "field": "staticR", "value": "c2" * 31}]
    # The pairing of the xx-link vector in noise-vectors.json: its first message carries the commitment, its second and third the two hellos with the nonces.
    session = {"vector": "xx-link", "nonceI": N, "nonceR": M, "staticI": "7b4e909bbe7ffe44c465a220037d608ee35897d31ef972f07f74892cb0f73f13",
               "staticR": "7b0d47d93427f8311160781c7c733fd89f88970aef490d8aa0ee19a4cb8a1b14", "commit": "2d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0", "code": "283272"}
    gaps = []

    def gap(name, last, now, out):
        gaps.append({"name": name, "last": last, "now": now, "out": out})

    gap("the first attempt", None, 0, True)
    gap("the first attempt, at any time", None, 987654321, True)
    gap("29.999 seconds after the last", 1000, 30999, False)
    gap("exactly 30 seconds after the last", 1000, 31000, True)
    gap("a minute after the last", 1000, 61000, True)
    gap("at the same instant", 1000, 1000, False)
    gap("the clock went back", 31000, 1000, False)
    gap("now is negative", 1000, -1, False)
    gap("last is negative", -5, 100000, False)
    gap("now is text", 1000, "31000", False)
    gap("last is text", "1000", 31000, False)
    gap("now is true", 1000, True, False)
    gap("now is null", 1000, None, False)
    windows = []

    def window(name, start, now, out):
        windows.append({"name": name, "start": start, "now": now, "out": out})

    window("the moment it opens", 5000, 5000, True)
    window("one millisecond before 2 minutes", 5000, 124999, True)
    window("exactly 2 minutes", 5000, 125000, False)
    window("long after", 5000, 900000, False)
    window("the clock went back", 5000, 4999, False)
    window("the start is text", "5000", 6000, False)
    window("the start is null", None, 6000, False)
    window("now is negative", 0, -1, False)
    offers = []

    def offer(name, offered, now, out):
        offers.append({"name": name, "offered": offered, "now": now, "out": out})

    offer("just offered", 5000, 5000, False)
    offer("one millisecond before 2 minutes", 5000, 124999, False)
    offer("exactly 2 minutes: expired", 5000, 125000, True)
    offer("long after", 5000, 900000, True)
    offer("the clock went back: expired", 5000, 4999, True)
    offer("the offer time is text: expired", "5000", 6000, True)
    offer("the offer time is null: expired", None, 6000, True)
    offer("now is negative: expired", 0, -1, True)
    out = {"version": 1, "digits": 6, "commitLabel": "notchmeow-link pairing commit v1", "codeLabel": "notchmeow-link pairing code v1", "gapMs": 30000, "windowMs": 120000, "offerTimeoutMs": 120000,
           "commits": commits, "codes": codes, "invalid": invalid, "session": session, "gapCases": gaps, "windowCases": windows, "offerCases": offers}
    out.update(pairing_machine_cases())
    # @@PAIRING-KEYS
    return out
def pairing_machine_cases():
    """The two pairing machines, row by row. N and M are the initiator's and the responder's nonces, SI and SR their static keys, C the commitment of N under SI
    (the values of pairing-cases.json); 479411 is the code of the four."""
    N, M, SI, SR = "a1" * 32, "b1" * 32, "c1" * 32, "c2" * 32
    C = "4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d"
    D = "63cdd5031f2d4bdd441b126924ba504fac75a6232f81ad2870b49ab0cfc02934"      # another commitment
    CODE = "479411"
    # The owner's rule (2026-10-14): a hello whose device id is this machine's own id is refused as own-id; a hello whose device id is paired under another key is
    # refused as id-key-mismatch (the user removes the device first to re-pair). A machine knows its own id (own_id) and its paired devices (paired: id -> key).
    OWN, PEER, OTHER = "d1" * 16, "e1" * 16, "f1" * 32      # this machine's id, another paired device's id, and a key that is not the one stored for it
    FRESH = "e2" * 16                                       # a device id that is neither OWN nor PEER: the id of a new peer, in the rows that do not test ids
    rows, irows, trips = [], [], []

    def out(state, send=(), notify=None, because=None):
        return {"state": state, "send": list(send), "notify": notify, "because": because}

    def cfg(state, paired):
        return {**state, "own_id": OWN, "paired": paired}

    def rhello(pid, static=SI):
        return {"reveal": {"nonce": N, "static": static, "own": SR, "peerId": pid}, "now": 2000}

    def ihello(pid, peer=SR):
        return {"nonce": M, "peerStatic": peer, "peerId": pid, "now": 2000}

    def ridle(seen=(), last=None):
        return {"s": "idle", "seen": list(seen), "last": last}

    def committed(start=1000, seen=None, last=None, commit=C):
        return {"s": "committed", "commit": commit, "start": start, "nonce": M, "seen": [{"commit": commit, "at": start}] if seen is None else seen, "last": start if last is None else last}

    def coded(mine=None, theirs=None, start=1000, seen=None, last=None):
        return {"s": "coded", "start": start, "code": CODE, "mine": mine, "theirs": theirs, "seen": [{"commit": C, "at": start}] if seen is None else seen, "last": start if last is None else last}

    def reveal(nonce=N, static=SI, own=SR, now=2000):
        return {"reveal": {"nonce": nonce, "static": static, "own": own, "peerId": FRESH}, "now": now}

    def r(name, state, event, want):
        rows.append({"name": name, "state": state, "event": event, "out": want})

    yes_sent, no_sent = [{"pair": "yes"}], [{"pair": "no"}]
    # The responder: the first message arrives with the commitment.
    r("a commitment starts a pairing: the responder's nonce goes out", ridle(), {"commit": C, "nonce": M, "now": 1000}, out(committed(), [{"nonce": M}], "nonce-sent"))
    r("a commitment of 31 bytes", ridle(), {"commit": C[:-2], "nonce": M, "now": 1000}, out(ridle(), because="commit-length"))
    r("a nonce of 31 bytes from the app", ridle(), {"commit": C, "nonce": M[:-2], "now": 1000}, out(ridle(), because="commit-length"))
    r("a commitment in capitals is not a commitment", ridle(), {"commit": C.upper(), "nonce": M, "now": 1000}, out(ridle(), because="commit-length"))
    r("the same commitment again a minute later: replayed", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 61000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="commit-replayed"))
    r("the same commitment again after 10 seconds is named a replay, not too soon", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 11000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="commit-replayed"))
    r("the same commitment after the window has closed is a new attempt, and the old entry goes", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 121000},
      out(committed(121000), [{"nonce": M}], "nonce-sent"))
    r("another commitment 19 seconds after the last attempt: too soon", ridle([{"commit": C, "at": 1000}], 1000), {"commit": D, "nonce": M, "now": 20000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="attempt-too-soon"))
    r("another commitment exactly 30 seconds after", ridle([{"commit": C, "at": 1000}], 1000), {"commit": D, "nonce": M, "now": 31000},
      out(committed(31000, [{"commit": C, "at": 1000}, {"commit": D, "at": 31000}], commit=D), [{"nonce": M}], "nonce-sent"))
    r("a commitment during a pairing", committed(), {"commit": D, "nonce": M, "now": 40000}, out(ridle([{"commit": C, "at": 1000}], 1000), because="unexpected"))
    # The third message: the reveal.
    r("a reveal with no commitment before it", ridle(), reveal(), out(ridle(), because="no-commit"))
    r("the reveal matches: the code is shown", committed(), reveal(), out(coded(), notify="show-code"))
    r("the reveal one millisecond before the window closes", committed(), reveal(now=120999), out(coded(), notify="show-code"))
    r("the reveal exactly when the window closes: too late", committed(), reveal(now=121000), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-late"))
    r("a reveal long after the window", committed(), reveal(now=900000), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-late"))
    r("a reveal of another nonce than the one committed", committed(), reveal(nonce=M), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal under another static key than the one committed", committed(), reveal(static=SR), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal that is the commitment itself", committed(), reveal(nonce=C), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal with a nonce of 31 bytes", committed(), reveal(nonce=N[:-2]), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-length"))
    r("a reveal with no key of its own", committed(), {"reveal": {"nonce": N, "static": SI}, "now": 2000}, out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-length"))
    r("a second reveal once the code is shown", coded(), reveal(), out(ridle([{"commit": C, "at": 1000}], 1000), because="unexpected"))
    # The answers.
    r("the user says they match", coded(), {"user": "yes", "now": 3000}, out(coded(mine="yes"), yes_sent))
    r("the user says they match after the other side did: the key is stored", coded(theirs="yes"), {"user": "yes", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), yes_sent, "store"))
    r("the other side says they match after the user did: the key is stored", coded(mine="yes"), {"peer": "yes", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "store"))
    r("the other side says they match first", coded(), {"peer": "yes", "now": 3000}, out(coded(theirs="yes")))
    r("the user says they do not match", coded(), {"user": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("the user says no after the other side said yes: nothing is stored", coded(theirs="yes"), {"user": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("the other side says no", coded(mine="yes"), {"peer": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"))
    r("an answer that is not exactly yes is a no", coded(), {"user": "YES", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("an answer of true is a no", coded(), {"peer": True, "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"))
    r("an answer when the window has closed", coded(mine="yes"), {"peer": "yes", "now": 121000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "window-closed"))
    r("a click before there is a code is ignored", committed(), {"user": "yes", "now": 3000}, out(committed()))
    r("an event the machine does not know is ignored", committed(), {"surprise": True}, out(committed()))
    r("the initiator's hello names this machine's own id: refused as own-id", cfg(committed(), {}), rhello(OWN),
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {}), because="own-id"))
    r("the initiator's hello names a new id: the code is shown", cfg(committed(), {}), rhello(PEER), out(cfg(coded(), {}), notify="show-code"))
    r("the initiator's hello names a paired id under another key: refused as id-key-mismatch", cfg(committed(), {PEER: OTHER}), rhello(PEER),
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: OTHER}), because="id-key-mismatch"))
    r("the initiator's hello names a paired id under the same key: the code is shown", cfg(committed(), {PEER: SI}), rhello(PEER), out(cfg(coded(), {PEER: SI}), notify="show-code"))
    r("the initiator's hello has no device id, and this machine knows its ids: refused as reveal-length", cfg(committed(), {PEER: OTHER}),
      {"reveal": {"nonce": N, "static": SI, "own": SR}, "now": 2000}, out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: OTHER}), because="reveal-length"))
    # The owner's rules (2026-10-14, narrowing): a hello with no device id is refused whether or not this machine knows its own id or a paired device, and an all-zero
    # device id is refused as device-id, the reason the hello decoder uses. The pins below check the order of the checks (commitment and nonce before the id).
    r("the initiator's hello has no device id, and this machine knows no ids: refused as reveal-length", committed(),
      {"reveal": {"nonce": N, "static": SI, "own": SR}, "now": 2000}, out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-length"))
    r("the initiator's hello names the all-zero id: refused as device-id", committed(), rhello("00" * 16), out(ridle([{"commit": C, "at": 1000}], 1000), because="device-id"))
    r("the initiator's hello names a paired id under the same key, but with another nonce: refused as reveal-mismatch, the commitment is checked first",
      cfg(committed(), {PEER: SI}), {"reveal": {"nonce": M, "static": SI, "own": SR, "peerId": PEER}, "now": 2000},
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: SI}), because="reveal-mismatch"))
    r("the initiator's hello names this machine's own id, which is also a paired id: refused as own-id, not id-key-mismatch", cfg(committed(), {OWN: OTHER}), rhello(OWN),
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {OWN: OTHER}), because="own-id"))
    r("the initiator's hello names a paired id under another key: nothing is sent, no notice is raised, and the cause is only the local reason", cfg(committed(), {PEER: OTHER}), rhello(PEER),
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: OTHER}), [], None, "id-key-mismatch"))
    # The fail-closed rule (2026-10-15): a machine whose own id, a paired id or a paired key is not canonical (an id is 32 lower-case hex digits, a key 64) refuses
    # every hello as device-id; it does not look the peer up, so a capital letter cannot make a paired id look new. CF is the commitment of N under OTHER.
    CF = "bc87c40fe71ab7f887c2b611c32adc5120c095f8526eb6c55a2cdd35da78a3eb"
    UPPER_PEER = PEER.upper()
    r("the initiator's hello names a paired id that is held in capitals, under another key: refused as device-id, not shown as a new id",
      cfg(committed(commit=CF), {UPPER_PEER: SI}), rhello(PEER, static=OTHER), out(cfg(ridle([{"commit": CF, "at": 1000}], 1000), {UPPER_PEER: SI}), because="device-id"))
    r("this machine's own id is held in capitals: the initiator's hello with the lower-case id is refused as device-id",
      {**committed(), "own_id": OWN.upper(), "paired": {}}, rhello(PEER), out({**ridle([{"commit": C, "at": 1000}], 1000), "own_id": OWN.upper(), "paired": {}}, because="device-id"))
    r("a paired key held in capitals: the initiator's hello with that id is refused as device-id, not as id-key-mismatch", cfg(committed(), {PEER: SI.upper()}), rhello(PEER),
      out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: SI.upper()}), because="device-id"))
    # The owner's rule (2026-10-14, null own id): an own_id of None is present and not an id, so it is not the unconfigured case: every hello with a valid id is refused as device-id.
    r("this machine's own id is null (no paired devices): the initiator's hello with a new id is refused as device-id, not shown as a new id",
      {**committed(), "own_id": None, "paired": {}}, rhello(PEER), out({**ridle([{"commit": C, "at": 1000}], 1000), "own_id": None, "paired": {}}, because="device-id"))

    def iidle(last=None):
        return {"s": "idle", "last": last}

    def started(start=1000):
        return {"s": "started", "nonce": N, "static": SI, "start": start, "last": start}

    def icoded(mine=None, theirs=None, start=1000):
        return {"s": "coded", "start": start, "code": CODE, "mine": mine, "theirs": theirs, "last": start}

    def second(nonce=M, peer=SR, now=2000):
        return {"nonce": nonce, "peerStatic": peer, "peerId": FRESH, "now": now}

    def i(name, state, event, want):
        irows.append({"name": name, "state": state, "event": event, "out": want})

    # The initiator.
    i("the user starts a pairing: the commitment goes out", iidle(), {"start": {"nonce": N, "static": SI}, "now": 1000}, out(started(), [{"commit": C}], "commit-sent"))
    i("a start 19 seconds after the last attempt: too soon", iidle(1000), {"start": {"nonce": N, "static": SI}, "now": 20000}, out(iidle(1000), because="attempt-too-soon"))
    i("a start exactly 30 seconds after", iidle(1000), {"start": {"nonce": N, "static": SI}, "now": 31000}, out({"s": "started", "nonce": N, "static": SI, "start": 31000, "last": 31000}, [{"commit": C}], "commit-sent"))
    i("a start with a nonce of 31 bytes", iidle(), {"start": {"nonce": N[:-2], "static": SI}, "now": 1000}, out(iidle(), because="start-length"))
    i("a start during a pairing", started(), {"start": {"nonce": N, "static": SI}, "now": 5000}, out(iidle(1000), because="unexpected"))
    i("the other side's nonce before any commitment of ours", iidle(), second(), out(iidle(), because="no-commit"))
    i("the other side's nonce: the reveal goes out and the code is shown", started(), second(), out(icoded(), [{"reveal": N}], "show-code"))
    i("the other side's nonce one millisecond before the window closes", started(), second(now=120999), out(icoded(), [{"reveal": N}], "show-code"))
    i("the other side's nonce exactly when the window closes: nothing is revealed", started(), second(now=121000), out(iidle(1000), because="reveal-late"))
    i("a second nonce once the code is shown", icoded(), second(), out(iidle(1000), because="nonce-repeated"))
    i("a nonce of 31 bytes", started(), second(nonce=M[:-2]), out(iidle(1000), because="nonce-length"))
    i("no static key from the other side", started(), {"nonce": M, "now": 2000}, out(iidle(1000), because="nonce-length"))
    i("the user says they match", icoded(), {"user": "yes", "now": 3000}, out(icoded(mine="yes"), yes_sent))
    i("both say they match: the key is stored", icoded(theirs="yes"), {"user": "yes", "now": 3000}, out(iidle(1000), yes_sent, "store"))
    i("the other side says no", icoded(mine="yes"), {"peer": "no", "now": 3000}, out(iidle(1000), [], "discard", "said-no"))
    i("the user says no", icoded(), {"user": "no", "now": 3000}, out(iidle(1000), no_sent, "discard", "said-no"))
    i("an answer when the window has closed", icoded(), {"user": "yes", "now": 121000}, out(iidle(1000), [], "discard", "window-closed"))
    i("a click before there is a code is ignored", started(), {"user": "yes", "now": 3000}, out(started()))
    i("the responder's hello names this machine's own id: refused as own-id", cfg(started(), {}), ihello(OWN), out(cfg(iidle(1000), {}), because="own-id"))
    i("the responder's hello names a new id: the reveal goes out and the code is shown", cfg(started(), {}), ihello(PEER), out(cfg(icoded(), {}), [{"reveal": N}], "show-code"))
    i("the responder's hello names a paired id under another key: refused as id-key-mismatch", cfg(started(), {PEER: OTHER}), ihello(PEER),
      out(cfg(iidle(1000), {PEER: OTHER}), because="id-key-mismatch"))
    i("the responder's hello names a paired id under the same key: the reveal goes out and the code is shown", cfg(started(), {PEER: SR}), ihello(PEER),
      out(cfg(icoded(), {PEER: SR}), [{"reveal": N}], "show-code"))
    i("the responder's hello has no device id, and this machine knows its ids: refused as nonce-length", cfg(started(), {}), {"nonce": M, "peerStatic": SR, "now": 2000},
      out(cfg(iidle(1000), {}), because="nonce-length"))
    # The owner's rules (2026-10-14, narrowing): the same as above for a machine that knows no ids, and an all-zero device id is refused as device-id.
    i("the responder's hello has no device id, and this machine knows no ids: refused as nonce-length", started(), {"nonce": M, "peerStatic": SR, "now": 2000},
      out(iidle(1000), because="nonce-length"))
    i("the responder's hello names the all-zero id: refused as device-id", started(), ihello("00" * 16), out(iidle(1000), because="device-id"))
    i("the responder's hello names a paired id that is held in capitals, under another key: refused as device-id, not shown as a new id", cfg(started(), {UPPER_PEER: SI}),
      ihello(PEER, peer=OTHER), out(cfg(iidle(1000), {UPPER_PEER: SI}), because="device-id"))
    # The owner's rule (2026-10-14, null own id): as above, an own_id of None is refused as device-id for every hello with a valid id.
    i("this machine's own id is null (no paired devices): the responder's hello with a new id is refused as device-id", {**started(), "own_id": None, "paired": {}},
      ihello(PEER), out({**iidle(1000), "own_id": None, "paired": {}}, because="device-id"))

    def trip(name, side, start, events, outs):
        trips.append({"name": name, "side": side, "from": start, "events": events, "out": outs})

    trip("the responder's whole pairing, both users agreeing", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(), {"user": "yes", "now": 5000}, {"peer": "yes", "now": 6000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(coded(), notify="show-code"), out(coded(mine="yes"), yes_sent), out(ridle([{"commit": C, "at": 1000}], 1000), [], "store")])
    trip("the responder, where the initiator reveals a different nonce than it committed", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(nonce=M), {"user": "yes", "now": 5000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"), out(ridle([{"commit": C, "at": 1000}], 1000))])
    trip("the responder, where the other user says the codes differ", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(), {"peer": "no", "now": 5000}, {"user": "yes", "now": 6000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(coded(), notify="show-code"), out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"), out(ridle([{"commit": C, "at": 1000}], 1000))])
    trip("the initiator's whole pairing, both users agreeing", "initiator", iidle(),
         [{"start": {"nonce": N, "static": SI}, "now": 1000}, second(), {"peer": "yes", "now": 4000}, {"user": "yes", "now": 5000}],
         [out(started(), [{"commit": C}], "commit-sent"), out(icoded(), [{"reveal": N}], "show-code"), out(icoded(theirs="yes")), out(iidle(1000), yes_sent, "store")])
    trip("the responder keeps its own id and its paired devices through a pairing, and refuses a paired id under another key", "responder", cfg(ridle(), {PEER: OTHER}),
         [{"commit": C, "nonce": M, "now": 1000}, rhello(PEER), {"user": "yes", "now": 5000}],
         [out(cfg(committed(), {PEER: OTHER}), [{"nonce": M}], "nonce-sent"), out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: OTHER}), because="id-key-mismatch"),
          out(cfg(ridle([{"commit": C, "at": 1000}], 1000), {PEER: OTHER}))])
    return {"machineNote": "responder and initiator: pair_responder_step and pair_initiator_step of reference.py, one event at a time ({state, event} -> out). machineTrips: the same over a script, starting from `from`, the state of one result being the state of the next event. "
                                  "because is the cause of a refusal and is what a port tests; a wrong nonce and a wrong static key give the same cause (reveal-mismatch) on purpose, because the commitment cannot tell them apart.",
            "responder": rows, "initiator": irows, "machineTrips": trips}
def filename_cases():
    cases, unique = [], []

    def ok(name, raw, out):
        cases.append({"name": name, "raw": raw, "out": {"ok": out}})

    def no(name, raw, reason):
        cases.append({"name": name, "raw": raw, "out": {"reject": reason}})

    # Names that are fine stay as they are. A dot at the start is the exception: it gets a _ in front (see the dot rows below).
    ok("a plain name", "report.pdf", "report.pdf")
    ok("accents, already composed", "r\u00e9sum\u00e9.docx", "r\u00e9sum\u00e9.docx")
    ok("Japanese", "\u65e5\u672c\u8a9e\u306e\u30d5\u30a1\u30a4\u30eb.txt", "\u65e5\u672c\u8a9e\u306e\u30d5\u30a1\u30a4\u30eb.txt")
    ok("an emoji", "\U0001F408.png", "\U0001F408.png")
    ok("a curly apostrophe and two spaces inside: the run becomes one space (the owner's rule, 2026-10-14)", "Sample\u2019s  notes v2.txt", "Sample\u2019s notes v2.txt")
    ok("a dot file gets a _ in front, so it shows", ".bashrc", "_.bashrc")
    ok("no extension", "Makefile", "Makefile")
    ok("several dots", "archive.v1.2.3.tar.gz", "archive.v1.2.3.tar.gz")
    ok("two dots inside the name", "a..b", "a..b")
    ok("two dots at the start, then letters: a name, not a way up, with a _ in front", "..hidden", "_..hidden")
    ok("a dash and a tilde at the start", "-rf~", "-rf~")
    ok("percent signs are not decoded", "%2e%2e%2fetc", "%2e%2e%2fetc")
    ok("shell characters are only characters", "$HOME `id` 100%.txt", "$HOME `id` 100%.txt")
    ok("DIVISION SLASH U+2215 is not a separator (the Finder shows it for /)", "a\u2215b.txt", "a\u2215b.txt")
    ok("COM0 is a device name since answer 2c (2026-10-14): a _ goes in front", "COM0", "_COM0")
    ok("COM10", "COM10.txt", "COM10.txt")
    ok("CONSOLE", "CONSOLE.txt", "CONSOLE.txt")
    ok("a device name as the extension is only an extension", "a.CON", "a.CON")
    ok("a dot file called .con has an empty stem: it gets a _ in front", ".con", "_.con")
    # Path traversal and absolute paths: rejected, never cut down to a last part.
    no("up and out", "../etc/passwd", "separator")
    no("up and out, Windows style", "..\\..\\Windows\\win.ini", "separator")
    no("up in the middle", "a/../../b", "separator")
    no("an absolute path", "/etc/passwd", "separator")
    no("a Windows drive path", "C:\\Windows\\System32\\cmd.exe", "separator")
    no("a UNC path", "\\\\server\\share\\f.txt", "separator")
    no("the home folder", "~/.ssh/authorized_keys", "separator")
    no("dot slash", "./x", "separator")
    no("a folder name with a slash at the end", "dir/", "separator")
    no("a lone backslash", "a\\b", "separator")
    no("a full-width solidus U+FF0F becomes / under NFKC", "\uff0fetc\uff0fpasswd", "separator")
    no("a full-width reverse solidus U+FF3C becomes \\ under NFKC", "a\uff3cb", "separator")
    no("full-width dots, a slash and dots", "\uff0e\uff0e\uff0fx", "separator")
    # Nothing left once trimmed.
    no("an empty name", "", "empty")
    no("one dot", ".", "empty")
    no("two dots", "..", "empty")
    no("three dots", "...", "empty")
    no("dots and spaces", ". . ", "empty")
    no("spaces only", "   ", "empty")
    no("an ideographic space only", "\u3000", "empty")
    no("a no-break space only", "\u00a0", "empty")
    no("full-width dots become .. under NFKC", "\uff0e\uff0e", "empty")
    # Controls, format characters and separators.
    no("a NUL in the middle", "a\x00b.txt", "invisible")
    no("only a NUL", "\x00", "invisible")
    ok("a newline becomes a space (the owner's rule, 2026-10-14)", "line\nbreak.txt", "line break.txt")
    ok("a tab becomes a space (the owner's rule, 2026-10-14)", "tab\there", "tab here")
    no("an escape", "esc\x1b[31m.txt", "invisible")
    no("DEL", "a\x7fb", "invisible")
    ok("NEL, U+0085, becomes a space (the owner's rule)", "a\x85b", "a b")
    ok("a line separator U+2028 becomes a space (the owner's rule)", "a\u2028b", "a b")
    ok("a paragraph separator U+2029 becomes a space (the owner's rule)", "a\u2029b", "a b")
    no("a right-to-left override: invoice[RLO]fdp.exe reads invoiceexe.pdf", "invoice\u202efdp.exe", "invisible")
    no("a left-to-right override", "\u202dx.txt", "invisible")
    no("an isolate, U+2066 and U+2069", "\u2066x\u2069.txt", "invisible")
    no("a left-to-right mark", "a\u200eb", "invisible")
    no("an Arabic letter mark", "\u061cx.txt", "invisible")
    no("a zero-width space", "a\u200bb.txt", "invisible")
    no("a byte order mark at the start", "\ufeffname.txt", "invisible")
    no("a word joiner", "a\u2060b", "invisible")
    no("a zero-width joiner (an emoji family is refused too: the cost of one simple rule)", "a\u200db", "invisible")
    no("a soft hyphen", "a\u00adb", "invisible")
    no("a tag character", "a\U000e0041b", "invisible")
    no("a Hangul choseong filler U+115F", "a\u115f.txt", "invisible")
    no("a Hangul jungseong filler U+1160", "a\u1160.txt", "invisible")
    no("a Hangul filler U+3164", "a\u3164.txt", "invisible")
    no("a half-width Hangul filler U+FFA0", "a\uffa0.txt", "invisible")
    # Every Default_Ignorable code point (Unicode DerivedCoreProperties) and U+2800 are refused as invisible too, one name per range family (the owner's rule, 2026-10-14).
    no("a braille blank U+2800 in the middle, which shows nothing", "a\u2800.txt", "invisible")
    no("a Khmer vowel sign U+17B5 in a name", "a\u17b5b.txt", "invisible")
    no("a Khmer vowel sign U+17B4 in a name", "a\u17b4b.txt", "invisible")
    no("a combining grapheme joiner U+034F", "a\u034fb.txt", "invisible")
    no("a variation selector U+FE0F", "a\ufe0fb.txt", "invisible")
    no("a variation selector supplement U+E0100", "a\U000e0100b.txt", "invisible")
    no("a Mongolian variation selector U+180B", "a\u180bb.txt", "invisible")
    no("a Mongolian variation selector U+180F", "a\u180fb.txt", "invisible")
    no("a zero-width joiner U+200D in a name", "a\u200db.txt", "invisible")
    no("a bidi isolate U+2066 in a name", "a\u2066b.txt", "invisible")
    no("a soft hyphen U+00AD in a name", "a\u00adb.txt", "invisible")
    no("a byte order mark U+FEFF in a name", "a\ufeffb.txt", "invisible")
    no("a language tag U+E0001", "a\U000e0001b.txt", "invisible")
    no("a musical symbol U+1D173 in a name", "a\U0001d173b.txt", "invisible")
    no("a shorthand format letter U+1BCA0 in a name", "a\U0001bca0b.txt", "invisible")
    no("an unassigned code point U+FFF0 in the specials range", "a\ufff0b.txt", "invisible")
    ok("a precomposed e with an acute, U+00E9, stays", "caf\u00e9.txt", "caf\u00e9.txt")
    ok("a CJK ideograph, U+65E5, stays", "\u65e5.txt", "\u65e5.txt")
    # Trailing dots and spaces, and spaces at the start.
    ok("a dot at the end goes", "file.txt.", "file.txt")
    ok("a space at the end goes", "file.txt ", "file.txt")
    ok("dots and spaces at the end go", "file.txt . .", "file.txt")
    ok("a space inside stays", "file. txt", "file. txt")
    ok("an ideographic space at the end goes", "trail\u3000", "trail")
    ok("spaces at the start go", "  lead.txt", "lead.txt")
    ok("a dot at the start: the spaces go, and the dot gets a _ in front", " .hidden", "_.hidden")
    # A dot at the start gets a _ in front, so the file shows. The 200-byte limit still holds after the _, and the device-name rule still holds on the result.
    ok("a dot file: .txt", ".txt", "_.txt")
    ok("a dot file: .zshrc", ".zshrc", "_.zshrc")
    ok("a dot file with an empty stem: .CON is not a device name, so only the _ goes in front", ".CON", "_.CON")
    ok("a dot and 199 letters: the _ takes the last byte of the limit", "." + "a" * 199, "_." + "a" * 198)
    ok("a dot and 220 letters with .txt: the cut after the _ keeps 200 bytes and the extension", "." + "a" * 220 + ".txt", "_." + "a" * 194 + ".txt")
    # Windows device names get a _ in front.
    ok("CON", "CON", "_CON")
    ok("con with an extension, any case", "con.txt", "_con.txt")
    ok("Con.tar.gz", "Con.tar.gz", "_Con.tar.gz")
    ok("PRN", "PRN", "_PRN")
    ok("AUX with a dot after a space", "aux .", "_aux")
    ok("NUL.tar.gz", "NUL.tar.gz", "_NUL.tar.gz")
    ok("COM1", "COM1", "_COM1")
    ok("com9.log", "com9.log", "_com9.log")
    # The owner's rule (answer 2c, 2026-10-14): COM0 and LPT0 are reserved, and COM or LPT followed by U+00B9, U+00B2 or U+00B3, in any case, with or without an extension.
    ok("COM0.txt", "COM0.txt", "_COM0.txt")
    ok("lpt0, lower case", "lpt0", "_lpt0")
    ok("Com0.tar.gz", "Com0.tar.gz", "_Com0.tar.gz")
    ok("COM with U+00B9, with an extension", "COM\u00b9.txt", "_COM\u00b9.txt")
    ok("lpt with U+00B2, lower case", "lpt\u00b2", "_lpt\u00b2")
    ok("COM with U+00B3, with a log extension", "COM\u00b3.log", "_COM\u00b3.log")
    ok("LPT with U+00B9", "LPT\u00b9", "_LPT\u00b9")
    # COM5 is not in the owner's list. The reference already reserves COM4 to COM9 and LPT4 to LPT9, and the owner's rule leaves that as it is: COM5 is reserved.
    ok("COM5.txt stays reserved, as COM4 to COM9 are today", "COM5.txt", "_COM5.txt")
    # A run of spaces is one space before the cut (the owner's rule), so these names are not cut at all any more: CON is not a device name with x.txt after it.
    ok("CON, 250 spaces, x.txt: the run is one space, so the name is CON x.txt", "CON" + " " * 250 + "x.txt", "CON x.txt")
    ok("nul, 250 spaces, q.bin: one space, so the name is nul q.bin", "nul" + " " * 250 + "q.bin", "nul q.bin")
    ok("COM1, 250 spaces, z.log: one space, so the name is COM1 z.log", "COM1" + " " * 250 + "z.log", "COM1 z.log")
    ok("full-width CON, 250 spaces, x.txt: one space, and NFKC is CON x.txt, not a device name", "\uff23\uff2f\uff2e" + " " * 250 + "x.txt", "\uff23\uff2f\uff2e x.txt")
    ok("lpt9 with a dot at the end", "lpt9.", "_lpt9")
    ok("a space before the dot", "CON .txt", "_CON .txt")
    ok("a superscript digit: COM\u00b9", "COM\u00b9.txt", "_COM\u00b9.txt")
    ok("CONIN$", "CONIN$", "_CONIN$")
    ok("CONOUT$ with an extension", "CONOUT$.log", "_CONOUT$.log")
    ok("full-width letters become CON under NFKC", "\uff23\uff2f\uff2e.txt", "_\uff23\uff2f\uff2e.txt")
    # Characters Windows does not allow, and the alternate data stream.
    ok("a colon", "a:b.txt", "a_b.txt")
    ok("a question mark", "what?.txt", "what_.txt")
    ok("angle brackets", "a<b>c.txt", "a_b_c.txt")
    ok("a quote, a pipe and a star", 'a"b|c*.txt', "a_b_c_.txt")
    ok("an alternate data stream", "file.txt:Zone.Identifier", "file.txt_Zone.Identifier")
    ok("a drive letter without a slash", "C:foo", "C_foo")
    # Normalization: the kept name is NFC, and nothing is folded to NFKC.
    ok("e and a combining acute become one letter", "re\u0301sume\u0301.docx", "r\u00e9sum\u00e9.docx")
    ok("Hangul jamo become a syllable", "\u1100\u1161.txt", "\uac00.txt")
    ok("the angstrom sign becomes the letter", "\u212b.txt", "\u00c5.txt")
    ok("a ligature stays a ligature (NFC, not NFKC)", "\ufb01le.txt", "\ufb01le.txt")
    # Length: 200 bytes of UTF-8, cut at a code point, with the extension kept.
    ok("200 bytes stay", "a" * 200, "a" * 200)
    ok("201 bytes are cut", "a" * 201, "a" * 200)
    ok("a long name keeps its extension", "a" * 300 + ".txt", "a" * 196 + ".txt")
    ok("cats: 70 four-byte emoji are cut to 49 and keep .png", "\U0001F408" * 70 + ".png", "\U0001F408" * 49 + ".png")
    ok("Japanese: 70 three-byte letters are cut to 65 and keep .txt", "\u65e5" * 70 + ".txt", "\u65e5" * 65 + ".txt")
    ok("200 bytes of two-byte letters stay", "\u00e9" * 100, "\u00e9" * 100)
    ok("201 bytes of two-byte letters are cut to 100", "\u00e9" * 100 + "a", "\u00e9" * 100)
    ok("a long extension is not an extension", "a" * 100 + "." + "b" * 150, "a" * 100 + "." + "b" * 99)
    ok("a cut that ends on spaces drops them", "a" * 199 + " " + "b" * 10, "a" * 199)
    ok("a letter with 300 combining marks is cut between marks", "a" + "\u0301" * 300, "\u00e1" + "\u0301" * 99)
    # The byte cut can leave nothing once trimmed: the name is refused as empty, as an empty name is. A _ from the leading-dot rule or the
    # device-name rule keeps a name, so those rows are saved.
    no("a dot and a space 120 times, then 20 letters: the cut leaves dots and spaces only, the trim takes them, nothing is saved", ". " * 120 + "x" * 20, "empty")
    no("a full-width dot and a space 120 times, then 20 letters: the cut leaves full-width dots, NFKC makes them dots, so nothing is saved", "\uff0e " * 120 + "x" * 20, "empty")
    ok("a dot, 250 spaces, x: one space, and the leading-dot rule gives it a _", "." + " " * 250 + "x", "_. x")
    ok("a dot, then 70 ideographic spaces, x: one space, and the leading-dot rule gives it a _", "." + "\u3000" * 70 + "x", "_. x")
    ok("a full-width dot, 250 spaces, x: one space, and the full-width dot is kept (NFC)", "\uff0e" + " " * 250 + "x", "\uff0e x")
    ok("_, 250 spaces, .txt: one space", "_" + " " * 250 + ".txt", "_ .txt")
    ok("a dot, 250 spaces, .txt: one space, and the leading-dot rule gives it a _", "." + " " * 250 + ".txt", "_. .txt")
    ok("._, 250 spaces, x: one space, and the leading-dot rule gives it a _", "._" + " " * 250 + "x", "_._ x")
    # A run of whitespace in a name collapses to one space, NBSP included (the owner's rule, 2026-10-14, answer 2b). It runs before the checks, the trim and the cut.
    ok("a run of 150 spaces collapses to one before the cut", "a" + " " * 150 + ".exe", "a .exe")
    ok("a space, a tab and a space collapse to one space", "a \t b.txt", "a b.txt")
    ok("two no-break spaces collapse to one space", "a\u00a0\u00a0b.txt", "a b.txt")
    no("only spaces, tabs and no-break spaces: nothing is left, refused as empty", " \t\u00a0 \t", "empty")
    ok("250 tabs collapse to one space before the cut, so the name is kept whole", "a" + "\t" * 250 + "b.txt", "a b.txt")
    ok("spaces at the start and at the end go", "  a.txt  ", "a.txt")
    ok("a line break between two words collapses to a space", "a\nb.txt", "a b.txt")
    ok("two ideographic spaces collapse to one space", "a\u3000\u3000b.txt", "a b.txt")
    # Not text.
    no("null", None, "not-text")
    no("a number", 5, "not-text")
    no("true", True, "not-text")
    no("a list", ["a"], "not-text")
    no("an object", {"a": 1}, "not-text")

    def free(name, wanted, taken, out, **more):
        unique.append({"name": name, "wanted": wanted, "taken": taken, **more, "out": out})

    free("nothing taken", "a.txt", [], "a.txt")
    free("another name taken", "a.txt", ["b.txt"], "a.txt")
    free("the name is taken", "a.txt", ["a.txt"], "a (1).txt")
    free("1 is taken too", "a.txt", ["a.txt", "a (1).txt"], "a (2).txt")
    free("the smallest free number", "a.txt", ["a.txt", "a (2).txt"], "a (1).txt")
    free("case does not matter", "a.txt", ["A.TXT"], "a (1).txt")
    # A known limit (the owner's decision, 2026-10-14): a stem that ends in a space keeps it before the numbered suffix, so two spaces can come out. Pinned, not changed.
    free("a stem that ends in a space: the numbered name has two spaces, a known limit", "a .txt", ["a .txt"], "a  (1).txt")
    free("a name that was typed decomposed is the same name", "\u00e9.txt", ["e\u0301.txt"], "\u00e9 (1).txt")
    free("no extension", "notes", ["notes"], "notes (1)")
    free("a dot file", ".bashrc", [".bashrc"], ".bashrc (1)")
    free("only the last extension is kept apart", "a.tar.gz", ["a.tar.gz"], "a.tar (1).gz")
    free("a long extension is not an extension", "a.verylongextensionname", ["a.verylongextensionname"], "a.verylongextensionname (1)")
    free("9999 numbers taken: give up", "a.txt", ["a.txt"], None, takenNumbered={"stem": "a", "ext": ".txt", "from": 1, "to": 9999})
    free("9998 numbers taken: the last one is free", "a.txt", ["a.txt"], "a (9999).txt", takenNumbered={"stem": "a", "ext": ".txt", "from": 1, "to": 9998})
    return {"version": 1, "bytesMax": 200, "extBytesMax": 16, "collisionMax": 9999,
            "note": "cases: raw is the name as sent, out is {ok: the saved name} or {reject: reason}. uniqueCases: taken is the names already in the folder, takenNumbered adds 'stem (n)ext' for n from..to; out is the name to use, or null.",
            "cases": cases, "uniqueCases": unique}
ID = "a1" * 16          # a transfer id, as hex
DEV = "b1" * 16         # a device id, as hex


def hx(text):
    return text.encode("utf-8").hex()


def frames_cases():
    ok, bad, hello, txt, pre, rec, recenc, limits = [], [], [], [], [], [], [], []

    def good(name, frame, hexstr):
        ok.append({"name": name, "frame": frame, "hex": hexstr})

    def no(name, hexstr, error):
        bad.append({"name": name, "hex": hexstr, "error": error})

    # The six frames: a type byte, the 16-byte id, the body; numbers big-endian. Written by hand from the layout in docs/LINK-CONTRACT.md.
    good("an offer", {"type": "offer", "id": ID, "size": 1048576, "name": "report.pdf", "kind": "application/pdf"},
         "01" + ID + "0000000000100000" + "000a" + hx("report.pdf") + "0f" + hx("application/pdf"))
    good("an offer of an empty file with no type", {"type": "offer", "id": ID, "size": 0, "name": "a.txt", "kind": ""}, "01" + ID + "0000000000000000" + "0005" + hx("a.txt") + "00")
    good("an offer with an emoji name", {"type": "offer", "id": ID, "size": 7, "name": "\U0001F408.png", "kind": "image/png"},
         "01" + ID + "0000000000000007" + "0008" + hx("\U0001F408.png") + "09" + hx("image/png"))
    good("an offer whose name holds a NUL (a good frame: the sanitizer refuses the name later)", {"type": "offer", "id": ID, "size": 1, "name": "a\x00b", "kind": ""},
         "01" + ID + "0000000000000001" + "0003" + "610062" + "00")
    good("an offer of the largest size a u64 holds (the receiver declines it as too large)", {"type": "offer", "id": ID, "size": 18446744073709551615, "name": "x", "kind": ""},
         "01" + ID + "ffffffffffffffff" + "0001" + "78" + "00")
    good("an offer of 4 GiB and one byte", {"type": "offer", "id": ID, "size": 4294967297, "name": "x", "kind": ""}, "01" + ID + "0000000100000001" + "0001" + "78" + "00")
    good("an offer with a name of 1020 bytes", {"type": "offer", "id": ID, "size": 1, "name": "a" * 1020, "kind": ""}, "01" + ID + "0000000000000001" + "03fc" + "61" * 1020 + "00")
    good("an offer with a type of 127 bytes", {"type": "offer", "id": ID, "size": 1, "name": "x", "kind": "k" * 127}, "01" + ID + "0000000000000001" + "0001" + "78" + "7f" + "6b" * 127)
    good("an accept", {"type": "accept", "id": ID}, "02" + ID)
    for reason, label in enumerate(["the user declined", "nobody answered in 2 minutes", "busy: this machine already has a transfer running", "too large", "the offer was not acceptable"]):
        good("a decline: " + label, {"type": "decline", "id": ID, "reason": reason}, "03" + ID + "%02x" % reason)
    good("a chunk at the start", {"type": "chunk", "id": ID, "offset": 0, "data": hx("hello")}, "04" + ID + "0000000000000000" + hx("hello"))
    good("a chunk at 32768", {"type": "chunk", "id": ID, "offset": 32768, "data": "ab"}, "04" + ID + "0000000000008000" + "ab")
    good("a chunk at the largest offset a u64 holds (the receiver refuses it as out of order)", {"type": "chunk", "id": ID, "offset": 18446744073709551615, "data": "00"},
         "04" + ID + "ffffffffffffffff" + "00")
    good("a done", {"type": "done", "id": ID}, "05" + ID)
    good("a cancel", {"type": "cancel", "id": ID}, "06" + ID)
    good("a pairing answer: they match", {"type": "pair-yes"}, "21")
    good("a pairing answer: they do not match", {"type": "pair-no"}, "22")

    no("no bytes", "", "empty")
    no("type 0", "00" + ID, "unknown-type")
    no("type 7", "07" + ID, "unknown-type")
    no("type 255", "ff" + ID, "unknown-type")
    no("only a type byte", "02", "truncated")
    no("a pair-yes with a byte too many", "2100", "trailing")
    no("a pair-no with a transfer id after it", "22" + ID, "trailing")
    no("type 0x20, just below the pairing answers", "20", "unknown-type")
    no("type 0x23, just above the pairing answers", "23", "unknown-type")
    no("an accept with 15 bytes of id", "02" + "a1" * 15, "truncated")
    no("an accept with a byte too many", "02" + ID + "00", "trailing")
    no("a done with a byte too many", "05" + ID + "00", "trailing")
    no("a cancel with a byte too many", "06" + ID + "00", "trailing")
    no("a decline with no reason", "03" + ID, "truncated")
    no("a decline with reason 5", "03" + ID + "05", "reason")
    no("a decline with reason 255", "03" + ID + "ff", "reason")
    no("a decline with a byte too many", "03" + ID + "0000", "trailing")
    no("a chunk with a short offset", "04" + ID + "00000000000000", "truncated")
    no("a chunk with an offset and no data", "04" + ID + "0000000000000000", "chunk-empty")
    no("an offer with no size", "01" + ID, "truncated")
    no("an offer with 9 bytes after the id", "01" + ID + "000000000000000000", "truncated")
    no("an offer with a name length of 0", "01" + ID + "0000000000000001" + "0000" + "00", "name-length")
    no("an offer with a name length of 1021", "01" + ID + "0000000000000001" + "03fd" + "61" * 1021 + "00", "name-length")
    no("an offer with a name length of 65535", "01" + ID + "0000000000000001" + "ffff", "name-length")
    no("an offer whose name stops short", "01" + ID + "0000000000000001" + "0005" + "616263", "truncated")
    no("an offer with no type length", "01" + ID + "0000000000000001" + "0001" + "78", "truncated")
    no("an offer whose type stops short", "01" + ID + "0000000000000001" + "0001" + "78" + "05" + "616263", "truncated")
    no("an offer with a byte after the type", "01" + ID + "0000000000000001" + "0001" + "78" + "00" + "00", "trailing")
    no("an offer with a type of 128 bytes", "01" + ID + "0000000000000001" + "0001" + "78" + "80" + "6b" * 128, "kind")
    no("an offer with a DEL in the type", "01" + ID + "0000000000000001" + "0001" + "78" + "01" + "7f", "kind")
    no("an offer with a control character in the type", "01" + ID + "0000000000000001" + "0001" + "78" + "01" + "1f", "kind")
    no("an offer with a non-ASCII type", "01" + ID + "0000000000000001" + "0001" + "78" + "02" + "c3a9", "kind")
    no("a name that is not UTF-8: a lone continuation start", "01" + ID + "0000000000000001" + "0002" + "c328" + "00", "utf8")
    no("a name with a UTF-16 surrogate encoded in UTF-8", "01" + ID + "0000000000000001" + "0003" + "eda080" + "00", "utf8")
    no("a name with an overlong slash", "01" + ID + "0000000000000001" + "0002" + "c0af" + "00", "utf8")
    no("a name beyond U+10FFFF", "01" + ID + "0000000000000001" + "0004" + "f4908080" + "00", "utf8")
    no("a name that stops in the middle of a character", "01" + ID + "0000000000000001" + "0002" + "e282" + "00", "utf8")

    # Limits that need long inputs: the reference and the apps build the frame from the recipe. 65494 is the most data in a chunk, so that the frame and the tag fill 65535 bytes.
    for n, out in ((1, "ok"), (65494, "ok"), (65495, "chunk-long")):
        limits.append({"name": "a chunk of %d bytes of data" % n, "id": ID, "offset": 0, "fill": "ab", "count": n, "out": out})

    def h(name, hexstr, out):
        hello.append({"name": name, "hex": hexstr, "out": out})

    def lenhex(text):
        return "%02x" % len(text.encode("utf-8"))

    air = "Sample’s test device"
    NONCE = "b1" * 32
    h("a hello", "01" + DEV + NONCE + "0a" + hx("Test rig 1"), {"id": DEV, "nonce": NONCE, "name": "Test rig 1"})
    h("a hello with a curly apostrophe", "01" + DEV + NONCE + lenhex(air) + hx(air), {"id": DEV, "nonce": NONCE, "name": air})
    h("a name of 63 bytes", "01" + DEV + NONCE + "3f" + "6e" * 63, {"id": DEV, "nonce": NONCE, "name": "n" * 63})
    h("a name of 64 bytes", "01" + DEV + NONCE + "40" + "6e" * 64, {"error": "name-length"})
    h("an empty name", "01" + DEV + NONCE + "00", {"error": "name-length"})
    h("a hello with no name length", "01" + DEV + NONCE, {"error": "truncated"})
    h("a hello with a nonce of 31 bytes", "01" + DEV + "b1" * 31, {"error": "truncated"})
    h("a name that stops short", "01" + DEV + NONCE + "05" + "616263", {"error": "truncated"})
    h("a byte after the name", "01" + DEV + NONCE + "01" + "6161", {"error": "trailing"})
    h("version 2", "02" + DEV + NONCE + "01" + "61", {"error": "version"})
    h("an all-zero device id", "01" + "00" * 16 + NONCE + "01" + "61", {"error": "device-id"})
    h("a name that is not UTF-8", "01" + DEV + NONCE + "02" + "c328", {"error": "utf8"})
    h("a newline in the name", "01" + DEV + NONCE + "03" + hx("a\nb"), {"error": "name-chars"})
    h("a right-to-left override in the name", "01" + DEV + NONCE + lenhex("a\u202eb") + hx("a\u202eb"), {"error": "name-chars"})
    h("a zero-width space in the name", "01" + DEV + NONCE + lenhex("a\u200bb") + hx("a\u200bb"), {"error": "name-chars"})
    h("a space at the start of the name", "01" + DEV + NONCE + "03" + hx(" ab"), {"error": "name-chars"})
    h("a space at the end of the name", "01" + DEV + NONCE + "03" + hx("ab "), {"error": "name-chars"})
    h("a name that is a Hangul filler alone", "01" + DEV + NONCE + lenhex("\u115f") + hx("\u115f"), {"error": "name-chars"})
    h("a name that is a zero-width space alone, U+200B", "01" + DEV + NONCE + lenhex("\u200b") + hx("\u200b"), {"error": "name-chars"})
    h("a name with a Khmer vowel sign, U+17B5", "01" + DEV + NONCE + lenhex("a\u17b5b") + hx("a\u17b5b"), {"error": "name-chars"})
    h("a name with a variation selector supplement, U+E0100", "01" + DEV + NONCE + lenhex("a\U000e0100b") + hx("a\U000e0100b"), {"error": "name-chars"})

    def t(name, record, out):
        txt.append({"name": name, "txt": record, "out": out})

    good_txt = {"id": "0123456789abcdef0123456789abcdef", "name": "Test rig 1", "v": "1"}
    t("an advert", good_txt, {"id": "0123456789abcdef0123456789abcdef", "name": "Test rig 1"})
    t("other keys are ignored", {**good_txt, "extra": "x", "path": "/etc"}, {"id": "0123456789abcdef0123456789abcdef", "name": "Test rig 1"})
    t("version 2", {**good_txt, "v": "2"}, {"error": "version"})
    t("the version is a number, not text", {**good_txt, "v": 1}, {"error": "version"})
    t("no version", {"id": good_txt["id"], "name": "Test rig 1"}, {"error": "version"})
    t("upper-case hex in the id", {**good_txt, "id": "0123456789ABCDEF0123456789ABCDEF"}, {"error": "device-id"})
    t("an id of 31 digits", {**good_txt, "id": "0123456789abcdef0123456789abcde"}, {"error": "device-id"})
    t("an id that is not hex", {**good_txt, "id": "z123456789abcdef0123456789abcdef"}, {"error": "device-id"})
    t("an all-zero id", {**good_txt, "id": "0" * 32}, {"error": "device-id"})
    t("no id", {"name": "Test rig 1", "v": "1"}, {"error": "device-id"})
    t("no name", {"id": good_txt["id"], "v": "1"}, {"error": "name-length"})
    t("a name of 64 bytes", {**good_txt, "name": "n" * 64}, {"error": "name-length"})
    t("a name with a bidi override", {**good_txt, "name": "a\u202eb"}, {"error": "name-chars"})
    t("a name with a newline", {**good_txt, "name": "a\nb"}, {"error": "name-chars"})
    t("a name that starts with a Hangul filler", {**good_txt, "name": "\u1160 Mac"}, {"error": "name-chars"})
    t("a name with a braille blank U+2800 in it", {**good_txt, "name": "a\u2800b"}, {"error": "name-chars"})
    t("a list is not a record", ["id"], {"error": "not-a-record"})
    t("null is not a record", None, {"error": "not-a-record"})
    # The owner's rule (2026-10-14): an advert whose id is this machine's own id is refused as own-id (its "ownId" is the machine's id in the row). The advert has no key,
    # so a paired id under another key is decided at the hello, not here.
    txt.append({"name": "an advert with this machine's own id: refused as own-id", "txt": good_txt, "ownId": good_txt["id"], "out": {"error": "own-id"}})
    txt.append({"name": "an advert with another id, while this machine has its own: accepted", "txt": good_txt, "ownId": "fedcba9876543210fedcba9876543210",
                "out": {"id": "0123456789abcdef0123456789abcdef", "name": "Test rig 1"}})
    # The owner's rule (2026-10-14): an advert is refused only for its own id and for the all-zero id; an all-zero id is device-id, as in the hello.
    txt.append({"name": "an all-zero advert, while this machine has its own id: refused as device-id", "txt": {**good_txt, "id": "0" * 32}, "ownId": "fedcba9876543210fedcba9876543210",
                "out": {"error": "device-id"}})
    # The fail-closed rule (2026-10-15): this machine's own id in capitals refuses the advert as device-id, it is not compared and not taken as another id.
    txt.append({"name": "an advert, while this machine's own id is held in capitals: refused as device-id", "txt": good_txt, "ownId": good_txt["id"].upper(),
                "out": {"error": "device-id"}})
    # The owner's rule (2026-10-14, null own id): a present own_id of None refuses the advert as device-id; an absent one (no "ownId" key in the row) is the unconfigured case.
    txt.append({"name": "an advert, while this machine's own id is null: refused as device-id", "txt": good_txt, "ownId": None, "out": {"error": "device-id"}})

    def p(name, hexstr, out):
        pre.append({"name": name, "hex": hexstr, "out": out})

    p("a pairing", "0101" + "00" * 16, {"mode": "pair", "id": "00" * 16})
    p("a transfer", "0102" + DEV, {"mode": "transfer", "id": DEV})
    p("version 2", "0201" + "00" * 16, {"error": "version"})
    p("version 0", "0001" + "00" * 16, {"error": "version"})
    p("mode 0", "0100" + DEV, {"error": "mode"})
    p("mode 3", "0103" + DEV, {"error": "mode"})
    p("a pairing that names a device", "0101" + DEV, {"error": "device-id"})
    p("a transfer with no device", "0102" + "00" * 16, {"error": "device-id"})
    p("17 bytes", "0101" + "00" * 15, {"error": "length"})
    p("19 bytes", "0101" + "00" * 17, {"error": "length"})
    p("no bytes", "", {"error": "length"})

    def r(name, stream, out):
        rec.append({"name": name, "hex": stream, "out": out})

    r("nothing yet", "", {"records": [], "rest": ""})
    r("one record", "0003aabbcc", {"records": ["aabbcc"], "rest": ""})
    r("two records in one read", "0001aa0002bbcc", {"records": ["aa", "bbcc"], "rest": ""})
    r("half a length", "00", {"records": [], "rest": "00"})
    r("a length and part of the body", "0005aabb", {"records": [], "rest": "0005aabb"})
    r("a record and the start of the next", "0001aa0003aa", {"records": ["aa"], "rest": "0003aa"})
    r("a record and half a length", "0001aa00", {"records": ["aa"], "rest": "00"})
    r("the largest length, and nothing yet", "ffff", {"records": [], "rest": "ffff"})
    r("a length of 0", "0000", {"error": "record-empty"})
    r("a length of 0 after a good record", "0001aa0000", {"error": "record-empty"})
    for payload, out in (("aa", {"hex": "0001aa"}), ("aabbcc", {"hex": "0003aabbcc"}), ("", {"error": "record-length"})):
        recenc.append({"name": "a record of %d byte(s)" % (len(payload) // 2), "payload": payload, "out": out})
    return {"version": 1,
            "note": "frames: the six frames, decoded and encoded (hex is the plaintext of one transport message). rejects: bytes that must not decode, with the error. limits: a chunk of count bytes of fill. "
                    "hello, txt, preamble, records and recordEncode: the other wire shapes. Strings in hex are bytes; names must be decoded as strict UTF-8 (a decoder that repairs bad bytes is wrong).",
            "noiseMax": 65535, "tag": 16, "idLen": 16, "protocolVersion": 1, "chunkMax": 65494, "chunkSize": 32768, "rawNameMax": 1020, "kindMax": 127, "deviceNameMax": 63, "sizeMax": 4294967296,
            "types": {"offer": 1, "accept": 2, "decline": 3, "chunk": 4, "done": 5, "cancel": 6, "pairYes": 33, "pairNo": 34}, "declineReasons": {"user": 0, "timeout": 1, "busy": 2, "tooLarge": 3, "badOffer": 4},
            "frames": ok, "rejects": bad, "limits": limits, "hello": hello, "txt": txt, "preamble": pre, "records": rec, "recordEncode": recenc}
ID1 = "01" * 16
ID2 = "02" * 16


def flow_cases():
    rcv, snd, trips, plans = [], [], [], []
    IDLE = {"s": "idle"}

    def offered(i=ID1, size=10, name="a.txt"):
        return {"s": "offered", "id": i, "size": size, "name": name}

    def receiving(got, size=10, i=ID1):
        return {"s": "receiving", "id": i, "size": size, "got": got}

    def offer(i=ID1, size=10, name="a.txt"):
        return {"frame": {"type": "offer", "id": i, "size": size, "name": name, "kind": ""}}

    def chunk(offset, n, i=ID1):
        return {"frame": {"type": "chunk", "id": i, "offset": offset, "data": "ab" * n}}

    def frame(t, i=ID1, **more):
        return {"frame": {"type": t, "id": i, **more}}

    def out(state, send=(), notify=None, abort=None):
        return {"state": state, "send": list(send), "notify": notify, "abort": abort}

    def decline(i, reason):
        return {"type": "decline", "id": i, "reason": reason}

    def r(name, state, event, want):
        rcv.append({"name": name, "state": state, "event": event, "out": want})

    # Offers. The name that is shown is the one that is saved; a size over 4 GiB or a bad name is declined without bothering the user.
    r("an offer: the card is shown", IDLE, offer(), out(offered(), notify="offer"))
    r("the card shows the sanitized name", IDLE, offer(name="a:b.txt"), out(offered(name="a_b.txt"), notify="offer"))
    r("an empty file is offered", IDLE, offer(size=0), out(offered(size=0), notify="offer"))
    r("exactly 4 GiB is offered", IDLE, offer(size=4294967296), out(offered(size=4294967296), notify="offer"))
    r("4 GiB and a byte is declined as too large", IDLE, offer(size=4294967297), out(IDLE, [decline(ID1, 3)]))
    r("a name with a path is declined as a bad offer", IDLE, offer(name="../x"), out(IDLE, [decline(ID1, 4)]))
    r("a name with a NUL is declined as a bad offer", IDLE, offer(name="a\x00b"), out(IDLE, [decline(ID1, 4)]))
    r("a second offer while one waits is declined as busy", offered(), offer(i=ID2), out(offered(), [decline(ID2, 2)]))
    r("a second offer during a transfer is declined as busy", receiving(4), offer(i=ID2), out(receiving(4), [decline(ID2, 2)]))
    r("the same offer again during a transfer is declined as busy", receiving(4), offer(), out(receiving(4), [decline(ID1, 2)]))
    # The user.
    r("accept: the transfer starts and an accept goes out", offered(), {"user": "accept"}, out(receiving(0), [{"type": "accept", "id": ID1}]))
    r("decline: back to idle with a decline", offered(), {"user": "decline"}, out(IDLE, [decline(ID1, 0)]))
    r("nobody answers: declined as timed out", offered(), {"timeout": True}, out(IDLE, [decline(ID1, 1)], notify="expired"))
    r("a click on accept with nothing offered does nothing", IDLE, {"user": "accept"}, out(IDLE))
    r("a timeout with nothing offered does nothing", IDLE, {"timeout": True}, out(IDLE))
    r("a timeout during a transfer does nothing", receiving(3), {"timeout": True}, out(receiving(3)))
    r("cancel by the user during a transfer", receiving(3), {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    r("a click on accept during a transfer does nothing", receiving(3), {"user": "accept"}, out(receiving(3)))
    r("the user cancels with nothing going on", IDLE, {"user": "cancel"}, out(IDLE))
    # The sender's frames.
    r("the sender withdraws an offer", offered(), frame("cancel"), out(IDLE, notify="withdrawn"))
    r("a cancel for another transfer is ignored", offered(), frame("cancel", ID2), out(offered()))
    r("a cancel with nothing going on is ignored", IDLE, frame("cancel"), out(IDLE))
    r("the sender cancels during a transfer", receiving(5), frame("cancel"), out(IDLE, notify="cancelled"))
    r("a cancel for another transfer during a transfer is ignored", receiving(5), frame("cancel", ID2), out(receiving(5)))
    r("data before the user accepted: closed", offered(), chunk(0, 1), out(IDLE, abort="unexpected"))
    r("done before the user accepted: closed", offered(), frame("done"), out(IDLE, abort="unexpected"))
    r("an accept from the sender: closed", offered(), frame("accept"), out(IDLE, abort="unexpected"))
    r("a chunk with nothing going on: closed", IDLE, chunk(0, 1), out(IDLE, abort="unexpected"))
    r("a done with nothing going on: closed", IDLE, frame("done"), out(IDLE, abort="unexpected"))
    r("an accept with nothing going on: closed", IDLE, frame("accept"), out(IDLE, abort="unexpected"))
    r("a decline with nothing going on: closed", IDLE, frame("decline", reason=0), out(IDLE, abort="unexpected"))
    r("a pairing answer during a transfer: closed", receiving(5), {"frame": {"type": "pair-yes"}}, out(IDLE, abort="unexpected"))
    r("a pairing answer with nothing going on: closed", IDLE, {"frame": {"type": "pair-no"}}, out(IDLE, abort="unexpected"))
    r("an accept during a transfer: closed", receiving(5), frame("accept"), out(IDLE, abort="unexpected"))
    r("a decline during a transfer: closed", receiving(5), frame("decline", reason=0), out(IDLE, abort="unexpected"))
    # Chunks: where the last one ended, never past the size.
    r("the first chunk", receiving(0), chunk(0, 4), out(receiving(4)))
    r("the next chunk", receiving(4), chunk(4, 4), out(receiving(8)))
    r("the last chunk reaches the size exactly", receiving(8), chunk(8, 2), out(receiving(10)))
    r("a replayed chunk: closed", receiving(4), chunk(0, 4), out(IDLE, abort="order"))
    r("the same chunk twice: closed", receiving(8), chunk(4, 4), out(IDLE, abort="order"))
    r("a skipped chunk: closed", receiving(4), chunk(8, 2), out(IDLE, abort="order"))
    r("a chunk past the size: closed", receiving(8), chunk(8, 3), out(IDLE, abort="overflow"))
    r("a chunk after the size is reached: closed", receiving(10), chunk(10, 1), out(IDLE, abort="overflow"))
    r("any chunk of an empty file: closed", receiving(0, size=0), chunk(0, 1), out(IDLE, abort="overflow"))
    r("a chunk of another transfer: closed", receiving(4), chunk(4, 4, ID2), out(IDLE, abort="id"))
    r("a done of another transfer: closed", receiving(10), frame("done", ID2), out(IDLE, abort="id"))
    r("done with every byte: the file is complete", receiving(10), frame("done"), out(IDLE, notify="complete"))
    r("done of an empty file", receiving(0, size=0), frame("done"), out(IDLE, notify="complete"))
    r("done one byte short: closed", receiving(9), frame("done"), out(IDLE, abort="short"))
    r("done at the start: closed", receiving(0), frame("done"), out(IDLE, abort="short"))

    def s(name, state, event, want):
        snd.append({"name": name, "state": state, "event": event, "out": want})

    SO, SS = {"s": "offered", "id": ID1}, {"s": "sending", "id": ID1}
    s("the receiver accepts", SO, frame("accept"), out(SS))
    s("the receiver accepts another transfer: closed", SO, frame("accept", ID2), out(IDLE, abort="id"))
    s("the receiver declines", SO, frame("decline", reason=0), out(IDLE, notify="declined"))
    s("the receiver declines another transfer: closed", SO, frame("decline", ID2, reason=0), out(IDLE, abort="id"))
    s("the receiver cancels before accepting", SO, frame("cancel"), out(IDLE, notify="cancelled"))
    s("the receiver sends data: closed", SO, chunk(0, 1), out(IDLE, abort="unexpected"))
    s("the receiver sends an offer: closed", SO, offer(), out(IDLE, abort="unexpected"))
    s("a pairing answer during the transfer: closed", SS, {"frame": {"type": "pair-yes"}}, out(IDLE, abort="unexpected"))
    s("an accept with nothing offered: closed", IDLE, frame("accept"), out(IDLE, abort="unexpected"))
    s("the receiver cancels during the transfer", SS, frame("cancel"), out(IDLE, notify="cancelled"))
    s("a second accept: closed", SS, frame("accept"), out(IDLE, abort="unexpected"))
    s("a decline during the transfer: closed", SS, frame("decline", reason=0), out(IDLE, abort="unexpected"))
    s("the user cancels an offer", SO, {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    s("the user cancels the transfer", SS, {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    s("the user cancels with nothing going on", IDLE, {"user": "cancel"}, out(IDLE))
    s("a cancel while idle is ignored", IDLE, frame("cancel"), out(IDLE))

    def trip(name, side, events, outs, start=IDLE):
        trips.append({"name": name, "side": side, "from": start, "events": events, "out": outs})

    # Whole transfers: the state after each event is the one before the next.
    trip("a transfer of 10 bytes in three chunks", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), chunk(4, 4), chunk(8, 2), frame("done")],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(receiving(8)), out(receiving(10)), out(IDLE, notify="complete")])
    trip("the second chunk is sent twice", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), chunk(4, 4), chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(receiving(8)), out(IDLE, abort="order")])
    trip("the first chunk is lost and the second arrives", "receiver", [offer(), {"user": "accept"}, chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(IDLE, abort="order")])
    trip("the sender stops one byte early", "receiver", [offer(), {"user": "accept"}, chunk(0, 9), frame("done")],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(9)), out(IDLE, abort="short")])
    trip("an offer nobody answers, then a new one", "receiver", [offer(), {"timeout": True}, offer(i=ID2)],
         [out(offered(), notify="offer"), out(IDLE, [decline(ID1, 1)], notify="expired"), out(offered(i=ID2), notify="offer")])
    trip("the user cancels half way and the sender's last chunk is already on its way", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), {"user": "cancel"}, chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"), out(IDLE, abort="unexpected")])
    trip("the offer is sent, the receiver accepts, then cancels", "sender", [frame("accept"), frame("cancel")], [out(SS), out(IDLE, notify="cancelled")], start=SO)
    trip("both users cancel at the same moment: the peer's cancel arrives while the sender is idle and is ignored", "sender", [{"user": "cancel"}, frame("cancel")],
         [out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"), out(IDLE)], start=SS)
    trip("both users cancel at the same moment: the peer's cancel arrives while the receiver is idle and is ignored", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), {"user": "cancel"}, frame("cancel")],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"), out(IDLE)])

    # The rules the app keeps around one connection (reference.py, "the rules the app keeps around one connection"): the machine's one transfer place, the one decline a connection
    # may make, and the first-frame clock. The expected answers are typed out here by hand. The peers of the place rows are the sample ids ID1 and ID2.
    places, conns, firsts = [], [], []

    def pl(holder=None, card=False):
        return {"holder": holder, "card": card}

    def pout(place_now, granted=None):
        return {"place": place_now, "granted": granted}

    def place(name, start, events, want):
        places.append({"name": name, "from": start, "events": events, "out": want})

    FREE = pl()
    place("a claim while the place is free is granted", FREE, [{"claim": ID1}], [pout(pl(ID1), True)])
    place("busy across two peers: another machine's offer is refused while one transfer runs", pl(ID1), [{"claim": ID2}], [pout(pl(ID1), False)])
    place("the same machine's second offer is refused while its own transfer runs", pl(ID1), [{"claim": ID1}], [pout(pl(ID1), False)])
    place("a card with buttons on the island refuses the claim", pl(None, True), [{"claim": ID1}], [pout(pl(None, True), False)])
    place("the place is free once its transfer ends, and another machine takes it", pl(ID1), [{"release": ID1}, {"claim": ID2}], [pout(FREE, None), pout(pl(ID2), True)])
    place("a release by a machine that holds nothing changes nothing", pl(ID1), [{"release": ID2}], [pout(pl(ID1), None)])
    place("a card going up and down around a claim", FREE, [{"card": True}, {"claim": ID1}, {"card": False}, {"claim": ID1}],
          [pout(pl(None, True), None), pout(pl(None, True), False), pout(FREE, None), pout(pl(ID1), True)])

    def cn(name, start, events, want):
        conns.append({"name": name, "from": start, "events": events, "out": want})

    def conn(state, declines):
        return {"state": state, "declines": declines}

    def cout(state, declines, send=(), notify=None, abort=None):
        return {"state": state, "declines": declines, "send": list(send), "notify": notify, "abort": abort}

    def refused(ev):
        return {**ev, "granted": False}

    cn("a too large offer is declined and the connection stays open", conn(IDLE, 0), [offer(size=4294967297)], [cout(IDLE, 1, [decline(ID1, 3)])])
    cn("a bad offer after one machine-made decline closes the connection and sends nothing", conn(IDLE, 1), [offer(name="../x")], [cout(IDLE, 1, abort="declines")])
    cn("a busy refusal is a machine-made decline", conn(IDLE, 0), [refused(offer())], [cout(IDLE, 1, [decline(ID1, 2)])])
    cn("a busy refusal after one machine-made decline closes the connection", conn(IDLE, 1), [refused(offer())], [cout(IDLE, 1, abort="declines")])
    cn("a second offer while one waits: declined busy, then the connection closes", conn(offered(), 0), [offer(i=ID2), offer(i=ID2)],
       [cout(offered(), 1, [decline(ID2, 2)]), cout(IDLE, 1, abort="declines")])
    cn("a valid offer after one machine-made decline still gets its card", conn(IDLE, 1), [offer()], [cout(offered(), 1, notify="offer")])
    cn("the user's no is not counted", conn(offered(), 1), [{"user": "decline"}], [cout(IDLE, 1, [decline(ID1, 0)])])
    cn("a timeout is not counted", conn(offered(), 1), [{"timeout": True}], [cout(IDLE, 1, [decline(ID1, 1)], notify="expired")])
    cn("the first-frame clock runs out with nothing offered: closed", conn(IDLE, 0), [{"silent": True}], [cout(IDLE, 0, abort="idle")])
    cn("a busy refusal does not stop the first-frame clock", conn(IDLE, 0), [refused(offer()), {"silent": True}], [cout(IDLE, 1, [decline(ID1, 2)]), cout(IDLE, 1, abort="idle")])
    cn("a cancel for a transfer we do not know does not stop the first-frame clock", conn(IDLE, 0), [frame("cancel", ID2), {"silent": True}],
       [cout(IDLE, 0), cout(IDLE, 0, abort="idle")])
    cn("an offer stops the first-frame clock: the late clock report is stale", conn(IDLE, 0), [offer(), {"silent": True}], [cout(offered(), 0, notify="offer"), cout(offered(), 0)])
    cn("a clock report during a transfer does nothing", conn(receiving(3), 0), [{"silent": True}], [cout(receiving(3), 0)])

    def first(name, handshake, now, want):
        firsts.append({"name": name, "handshake": handshake, "now": now, "out": want})

    first("the handshake is over: open", 0, 0, False)
    first("9999 ms after the handshake: open", 0, 9999, False)
    first("10000 ms after the handshake: closed", 0, 10000, True)
    first("long after: closed", 5000, 900000, True)
    first("the clock went back: closed", 5000, 4999, True)
    first("the handshake time is text: closed", "5000", 6000, True)
    first("the handshake time is null: closed", None, 6000, True)
    first("now is negative: closed", 0, -1, True)

    def plan(name, size, chunk_size, want):
        plans.append({"name": name, "size": size, "chunkSize": chunk_size, "out": want})

    plan("an empty file has no chunks", 0, 4, [])
    plan("one byte", 1, 4, [[0, 1]])
    plan("an exact multiple", 8, 4, [[0, 4], [4, 4]])
    plan("a remainder", 10, 4, [[0, 4], [4, 4], [8, 2]])
    plan("a size one over the chunk", 5, 4, [[0, 4], [4, 1]])
    plan("the real chunk size and one byte more", 32769, 32768, [[0, 32768], [32768, 1]])
    plan("two real chunks exactly", 65536, 32768, [[0, 32768], [32768, 32768]])
    return {"version": 1, "chunkSize": 32768, "sizeMax": 4294967296, "aborts": ["unexpected", "id", "order", "overflow", "short"],
            "note": "receiver and sender: receiver_step / sender_step of reference.py, one event at a time ({state, event} -> out). A frame in an event is a decoded frame as in frames.json. "
                    "trips: the same over a script, starting from `from`; out holds the result after each event, the state of one being the state the next starts from. chunkPlans: the offsets and lengths a sender cuts a file into.",
            "receiver": rcv, "sender": snd, "trips": trips, "chunkPlans": plans,
            "firstFrameMs": 10000, "places": places, "connections": conns, "firstFrame": firsts}
# @@BUILDERS


def render(obj, pretty):
    """Lists one case per line (easy to read and to diff); pretty: the whole file indented, for the Noise vectors. Non-ASCII is escaped, so an invisible character shows as an escape."""
    if pretty:
        return json.dumps(obj, indent=1) + "\n"
    out = []
    for k, v in obj.items():
        if isinstance(v, list):
            out.append('  "%s": [\n    %s\n  ]' % (k, ",\n    ".join(json.dumps(x) for x in v)))
        else:
            out.append('  "%s": %s' % (k, json.dumps(v)))
    return "{\n" + ",\n".join(out) + "\n}\n"


FILES = {  # file name: (builder, pretty)
    "noise-vectors.json": (noise_vectors, True),
    "pairing-cases.json": (pairing_cases, False),
    "filename-cases.json": (filename_cases, False),
    "frames.json": (frames_cases, False),
    "flow-cases.json": (flow_cases, False),
    # @@FILES
}


def main():
    check = "--check" in sys.argv
    bad = 0
    for name, (build, pretty) in FILES.items():
        text = render(build(), pretty)
        path = os.path.join(HERE, name)
        if check:
            have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if have != text:
                print(f"✗ {name} drifted from build_cases.py")
                bad = 1
            else:
                print(f"✓ {name} matches build_cases.py")
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"wrote {name} ({len(text)} bytes)")
    return bad


if __name__ == "__main__":
    sys.exit(main())
