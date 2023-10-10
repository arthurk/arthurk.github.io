+++
title = "Generating Ethereum Addresses in Python"
date = "2020-02-16"
+++

I've been wondering how long it would take to generate all Ethereum private keys with addresses on my laptop.

I know there is [not enough energy in our star system](https://bitcointalk.org/index.php?topic=7769.msg1010711#msg1010711) to do this in a reasonable timeframe, even on an imaginative computer that would use the absolute minimum of energy possible. This was more of a learning experience for me to get to know more about SHA-3 and KECCAK hashes, ECDSA curves, Public Keys and Ethereum addresses.

Due to its slow interpreter, Python is usually not a good choice when it comes to writing performant applications. The exception being Python modules which use an interface that calls C/C++ code. These modules are usually very fast, popular examples are [Tensorflow](https://www.tensorflow.org/) and [Numpy](https://numpy.org/). To generate Ethereum addresses we can use the following two Python modules which are both C based and have a good performance:

*   [coincurve](https://github.com/ofek/coincurve/): Cross-platform Python CFFI bindings for libsecp256k1
*   [pysha3](https://github.com/tiran/pysha3): SHA-3 wrapper for Python (with support for keccak)

Generating Ethereum addresses is a 3-step process:

1.  Generate a private key
2.  Derive the public key from the private key
3.  Derive the Ethereum address from the public key

Note that public keys and Ethereum addresses are not the same. Addresses are hashes of public keys. It's not possible to send funds to a public key.

## Step 1: Generate a private key

Ethereum private keys are based on [KECCAK-256 hashes](https://keccak.team/keccak.html). To generate such a hash we use the `keccak_256` function from the pysha3 module on a random 32 byte seed:

```python
import secrets
from sha3 import keccak_256

private_key = keccak_256(secrets.token_bytes(32)).digest()
```

Note that a KECCAK hash is not the same as a SHA-3 hash. KECCAK won a competition to become the SHA-3 standard but was slightly modified before it became standardized. Some SHA3 libraries such as pysha3 include the legacy KECCAK algorithm while others, such as the [Python hashlib module](https://docs.python.org/3.7/library/hashlib.html), only implement the official SHA-3 standard.

## Step 2: Derive the public key from the private key

To get our public key we need to sign our private key with an Elliptic Curve Digital Signature Algorithm (ECDSA). Ethereum uses the [secp256k1 curve ECDSA](https://en.bitcoin.it/wiki/Secp256k1). Coincurve uses this as a default so we don't need to explicitly specify it when calling the function:

```python
from coincurve import PublicKey

public_key = PublicKey.from_valid_secret(private_key).format(compressed=False)[1:]
```

The [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) states that the public key has to be a byte array of size 64.

By default coincurve uses the compressed format for public keys (libsecp256k1 was developed for Bitcoin where compressed keys are commonly used) which is 33 bytes in size. Uncompressed keys are 65 bytes in size. Additionally all public keys are prepended with a single byte to indicate if they are compressed or uncompressed. This means we first need to get the uncompressed 65 byte key (`compressed=False`) and then strip the first byte (`[1:]`) to get our 64 byte Ethereum public key.

## Step 3: Derive the Ethereum address from the public key

We can now generate our Ethereum address:

```python
addr = keccak_256(public_key).digest()[-20:]
```

As specified in the [Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) we take the right most 20 bytes of the 32 byte KECCAK hash of the corresponding ECDSA public key.

## Full Example

This is the full example code from the above steps. It generates a random private key, derives the address and prints them in hex format:

```python
from secrets import token_bytes
from coincurve import PublicKey
from sha3 import keccak_256

private_key = keccak_256(token_bytes(32)).digest()
public_key = PublicKey.from_valid_secret(private_key).format(compressed=False)[1:]
addr = keccak_256(public_key).digest()[-20:]

print('private_key:', private_key.hex())
print('eth addr: 0x' + addr.hex())

### Output ###
# private_key: 7bf19806aa6d5b31d7b7ea9e833c202e51ff8ee6311df6a036f0261f216f09ef
# eth addr: 0x3db763bbbb1ac900eb2eb8b106218f85f9f64a13
```

## Conclusion

I used the Python `timeit` module to do [a quick benchmark](https://gist.github.com/arthurk/fbc876951379e2b0c889ea71b5167b4e) with the above code. The result is that my laptop can generate 18k addresses per second on a single cpu core. Using all 4 cpu cores that's 72k addresses per second, ~6.2 billion (6.220.800.000) addresses per day or around two trillion (2.270.592.000.000) addresses per year.

Ethereum's address space is 2^160\. This means that by using this method it would take my laptop 643665439999999976814879449351716864 (six hundred and forty-three decillion ...) years to generate all Ethereum private keys with addresses.
