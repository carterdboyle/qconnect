# Qconnect 

This web application uses a Javascript driven console for the front-end for a retro feel which is inspired by the existing repo for the Python based console application at [qpigeon](github.com/carterdboyle/qpigeon).
I used the same Post-Quantum secure libraries (liboqs) for encryption, same algorithms (Kyber512 for KEM, and Dilithium2 for signing) and same protocol (can be found in docs/protocol.pdf). However, for this application I wanted to host the application on a server rather than relying on cumbersome docker containers. 

Ruby on Rails was used as the framework for the web application and served out Javascript with the HTML template, which basically controls everything and has a compiled WASM of the liboqs which was built with shims and can be found at my fork @[liboqs-wasm](github.com/carterdboyle/liboqs-wasm).

## Idea / Premise

The idea of this web application is that it provides an E2E encrypted channel for communication that would be very secure and resistant to decryption, even from a landscape where quantum computing is prevalent. It boasts secure signing and KEM algorithms (Dilithium2 and Kyber512), respectively, and a protocol that is highly resistant to attacks like MITM (man-in-the-middle) or replay. This is achieved by including unique nonces in the signature as well as timestamps and a time threshold verification (see the protocol.pdf for more information).

No plaintext is sent over the communication channel; only cipher text is ever broadcasted through Redis or HTTP. No shared secret for symmetric encryption is ever sent due to the inclusion of the KEM protocol. The user must use the decapsulation algorithm to receive the secret key used for encryption using their own locally stored secret kem key. The browsers perform the signing, decapsulation and AES encryption/decrpytion for the client side and the Rails server does verification, and key encapsulation as well as any challenges for key registration and authentication. 

## Current live service / limitations

The service is live at [https://chat.carterdboyle.ca](https://chat.carterdboyle.ca) if you want to try it. However, note that currently the messages are stored locally in your browser and if they are deleted from the local IndexedDB they are gone forever as they are only stored on the server in an encrypted form and the secret keys are neccessary to decrypt them and can only be found saved locally. If you do need to move machines you can copy your local secret keys (signing and kem) to the new machine and manually create the indexedDB environment. 

## Installation

- If you want to run a local copy of the server for experimenting than clone this repo with `git clone https//github.com/carterdboyle/qconnect.git` and `cd qconnect`.
- Ensure that `rails` is installed on your machine (follow [guide](https://guides.rubyonrails.org/install_ruby_on_rails.html) if not installed).
- After installing Rails (8+ recommended) run `bundle install` to install all Rails dependencies.
- Start the server with `rails s`. You may need to migrate `db` files by calling `rails db:migrate` to set up the SQLite database for testing.
- Connect to the server by navigating to `http://localhost:3000/` or `http://127.0.0.1:3000` in your browser of choice, assuming the default settings are unchanged. 

## Functionality

The user can see a list of help commands by typing in 'help' in the command prompt.

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/d522dd72-8680-4e40-a6f5-52934654036d" /></p>

---

### Registration

The first step in the registration flow is to assign a handle. It will be created if that user does not already exist. I have set up the happy path full-stack system test for two users communicating in the chat using Rails' built-in Capybara testing suite and taken screenshots along the way.

#### Assigning a handle

Type `handle <user>` into the command prompt. A user will be assigned and a session will be created. 

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/95fc902c-1505-4b73-9c74-30ef433ffa79" /></p>

#### Generating keypairs for signing and KEM

Type `genkeys` into the command prompt. Keys will be generated **ONCE** for the assigned user.

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/c58cdc44-24a1-4b19-81fd-0c52e240e8f4" /></p>

#### Registering keys to the server

Type `register` after the keys have been generated, into the console. The keys will be saved to the server (public keys).

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/8b6621a8-03c9-427b-a3af-dd01d42561a0" /></p>

Congratulations! Your account has been registered and you can now login into it, assuming that your browser has the keys. As of now, that is a limitation of the application in that you can only log in from the same browser to a given handle.

---

### Requesting a contact

To request a contact, the user must first login with the `login` cmd and then type in `request <contact> <optional message>`. If the user exists, there will be a successful message returned.

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/c5351b4d-0be2-4674-bbec-c433d310a7b1" /></p>

--- 

### Accepting/declining a contact request

To accept a pending contact request, simply type in `accept <request_id>`. To view requests and associated IDs type in `requests`. Here is an image of another user, "bob", accepting a request after first registering, signing in and viewing the requests.
To decline follow the same process and type `decline <request_id>` instead. 

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/71f64b21-401d-430d-956d-79012c8f0209" /></p>

---

### Viewing unread messages

To view any unread messages type in `inbox` into the console. If any party has sent any messages in a conversation then there will be a list of notifications displaying either `[no new]` or `[X new]` messages, depending on whether the receiver has opened the chat since last receiving a message from the peer. 

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/61755350-1998-4d2c-8561-1b26b771eb29" /></p>

In the above case, "alice" has sent 2 messages a few days ago so "bob" sees the notice `[2 new]` from `@alice`.

---

### Chatting with a user

To chat with another user type in `chat <handle>` into the console. You will see the chat window open and anything entered into the console will be sent as a message to the user, complete with timestamps and day dividers. 
There are notifications that lead any new, unread messages for easy communication of which messages are recent.

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/ba78ee7f-96a5-4baf-80f3-52b2b4be8594" /></p>

You can test with two different browsers on two different machines or using two different browsers on the same machine, like Chrome and Firefox, for example. If you have the chat open between two users the messages should come in instantaneously due to Rails' ActionCable functionality and the Redis server.

Note that if "bob" opens his chat then the amount of unread messages will be 0. Now, if "alice" sends another message from today and "bob" opens back up the chat he should see there is `1 new message!` (the same will be seen from the `inbox` cmd if he calls it beforehand). 

<p align="center"><img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/48bfcf24-183c-45cb-b8e1-fb23be4a3527" /></p>

Note that the date divider has printed out to show that this message has been received today. 

---

## Future Work

In the future it would be nice if the signing and KEM algorithms could be adjusted manually. It would be beneficial to allow the rotation of keys as well and to introduce the ability to switch machines easily. 

---

## Appendix - Protocol

### Definitions

$$
\begin{align*}
PS &:\ \text{Public key (for signing)}\\
SS &:\ \text{Secret key (for signing)}\\
PK &:\ \text{Public key (for KEM)}\\
SK &:\ \text{Secret key (for KEM)}\\
K &:\ \text{Symmetric encryption key}\\
N &:\ \text{List of used nonces}\\
B &:\ \text{Contact book}
\end{align*}
$$

$$
\begin{align*}
\text{Sign}_{SS}(M) &= S && \text{Signs message } M \text{ using private key } SS \text{ creating signature } S \text{.}\\
\text{Sign}_{PS}^{-1}(S, M) &= \{0,1\} && \text{Verifies message } M \text{ matches signature } S \text{ using public key } PS \text{.}\\
&&& \text{Outputs 1 when signature matches.}\\
\\
\text{KEM}_{PK}(K) &= C && \text{Encrypts the given key } K \text{ using public key } PK \text{.}\\
\text{KEM}^{-1}_{SK}(C) &= K && \text{Decrypts the given encrypted key } C \text{ using secret key } SK \text{.}\\
&&& \text{KEM stands for Key Encapsulation Mechanism.}\\
\\
\text{Enc}_{K}(M) &= C && \text{Encrypts the given message using symmetric key } K \text{.} \\
\text{Enc}^{-1}_{K}(C) &= M && \text{Decrypts the given ciphertext using symmetric key } K \text{.}\\
\\
\text{Now()} &= T && \text{Outputs the current timestamp.}
\end{align*}
$$

## Registration
$$
\text{Bob registers his keys with the server.}
$$
$$
\begin{align*}
\text{Bob has} &: PS_{\text{Bob}}, SS_{\text{Bob}}, PK_{\text{Bob}}, SK_{\text{Bob}}\\
\\
\\
\text{Bob sends to server} &: PS_{\text{Bob}}, PK_{\text{Bob}}
\\
\\
\text{Server calculates} &:\\
M &= \{0,1\}^{128}
&& \text{Generate signing challenge.}
\\
K &= \{0,1\}^{128}
&& \text{Generate KEM challenge.}
\\
C &= \text{KEM}_{PK_{\text{Bob}}}(K)
&& \text{Encapsulate KEM challenge.}
\\
\\
\text{Server sends to Bob} &: M, C
\\
\\
\text{Bob calculates} &:\\
S &= \text{Sign}_{SS_\text{Bob}}(M)
&& \text{Sign the signing challenge.}
\\
K' &= \text{KEM}^{-1}_{SK_\text{Bob}}(C)
&& \text{Decapsulate the KEM challenge.}
\\
\\
\text{Bob sends to Server} &:S, K'
\\
\\
\text{Server calculates} &:\\
S_\text{Verify} &= \text{Sign}^{-1}_{PS_{\text{Bob}}}(S, M)
&& \text{Verify the signature of the signing challenge.}
\\
K &= K'
&& \text{Verify the KEM challenge response is correct.}
\\
&&& \text{Once verified, Server records Bob's keys.}
\end{align*}
$$

## Contact Request and Accept

$$
\text{Bob adds Alice as a contact.}
$$

$$
\begin{align*}
\text{Bob has} &: SS_{\text{Bob}}, PS_{\text{Alice}}, T_{\text{Threshold}}, B, N\\
\text{Server has} &: PS_{\text{Bob}}, PS_{\text{Alice}}, T_{\text{Threshold}}, B, N\\
\text{Alice has} &: SS_{\text{Alice}}, PS_{\text{Bob}}, T_{\text{Threshold}}, B, N\\
\\
\text{Bob calculates} &:\\
T &= \text{Now}()
&& \text{Get current timestamp.}
\\
n &= \{0,1\}^{128} \text{ s.t. } (n, PS_{\text{Bob}}) \notin N
&& \text{Generate nonce.}
\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add nonce to list.}
\\
S &= \text{Sign}_{SS_{\text{Bob}}}(T||n||PS_{\text{Alice}})
&& \text{Sign contact request.}
\\
B &= B \cup \{(PS_{\text{Alice}}, PS_{\text{Bob}})\}
&& \text{Mark Alice as able to send messages to Bob.}
\\
\\
\text{Bob sends to server} &: S, T, n, PS_{\text{Alice}}
\\
\\
\text{Server calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Bob}}}(S, T||n||PS_{\text{Alice}})
&& \text{Verify contact request is from Bob.}
\\
T &\gt \text{Now}() - T_{\text{Threshold}}
&& \text{Verify contact request is recent.}
\\
(n, PS_{\text{Bob}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add old nonce to list.}
\\
B &= B \cup \{(PS_{\text{Alice}}, PS_{\text{Bob}})\}
&& \text{Mark Alice as able to send messages to Bob.}
\\
\\
\end{align*}
$$
$$
\begin{align*}
\text{Server sends to Alice} &: S, T, n
\\
\\
\text{Alice calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Bob}}}(S, T||n||PS_{\text{Alice}})
&& \text{Verify contact request is from Bob.}\\
&&& \text{If } S_{\text{Verify}} = 0 \text{, reject.}\\
T &\gt \text{Now}() - T_{\text{Threshold}}
&& \text{Verify contact request is recent.}
\\
(n, PS_{\text{Bob}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add old nonce to list.}
\\
B &= B \cup \{(PS_{\text{Alice}}, PS_{\text{Bob}})\}
&& \text{Mark Alice as able to send messages to Bob.}
\\
\\
T &= \text{Now}()
&& \text{Get current timestamp.}
\\
n &= \{0,1\}^{128} \text{ s.t. } (n, PS_{\text{Alice}}) \notin N
&& \text{Generate nonce.}
\\
N &= N \cup \{(n, PS_{\text{Alice}})\}
&& \text{Add nonce to list.}
\\
S &= \text{Sign}_{SS_{\text{Alice}}}(T||n||PS_{\text{Bob}})
&& \text{Sign contact request.}
\\
B &= B \cup \{(PS_{\text{Bob}}, PS_{\text{Alice}})\}
&& \text{Mark Bob as able to send messages to Alice.}\\
\\
\text{Alice sends to server} &: S, T, n, PS_{\text{Bob}}
\end{align*}
$$
$$
\begin{align*}
\text{Server calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Alice}}}(S, T||n||PS_{\text{Bob}})
&& \text{Verify contact request is from Alice.}\\
&&& \text{If } S_{\text{Verify}} = 0 \text{, reject.}\\
T &\gt \text{Now}() - T_{\text{Threshold}}
&& \text{Verify contact request is recent.}
\\
(n, PS_{\text{Alice}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Alice}})\}
&& \text{Add old nonce to list.}
\\
B &= B \cup {(PS_{\text{Bob}}, PS_{\text{Alice}})}
&& \text{Mark Bob as able to send messages to Alice.}
\\
\\
\text{Server sends to Bob} &: S, T, n
\\
\\
\text{Bob calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Alice}}}(S, T||n||PS_{\text{Bob}})
&& \text{Verify contact request is from Alice.}\\
&&& \text{If } S_{\text{Verify}} = 0 \text{, reject.}\\
T &\gt \text{Now}() - T_{\text{Threshold}}
&& \text{Verify contact request is recent.}
\\
(n, PS_{\text{Alice}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Alice}})\}
&& \text{Add old nonce to list.}
\\
B &= B \cup {(PS_{\text{Bob}}, PS_{\text{Alice}})}
&& \text{Mark Bob as able to send messages to Alice.}
\\
\end{align*}
$$

## Public Key (for KEM) Distribution

$$
\text{Alice sends a public key (for KEM) } PK_{\text{Alice}} \text{ to Bob.}
\begin{align*}
\text{Alice has} &: SS_{\text{Alice}}, PK_{\text{Alice}}\\
\text{Server has} &: PS_\text{Alice}\\
\text{Bob has} &: PS_{\text{Alice}}\\
\\
\text{Alice calculates} &:\\
S &= \text{Sign}_{SS_{\text{Alice}}}(PK_{\text{Alice}})
&& \text{Signs public key.}\\
\\
\text{Alice sends to Server} &: S, PK_{\text{Alice}}\\
\\
\text{Server calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Alice}}}(S, PK_{\text{Alice}})
&& \text{Verify message is from Alice.}\\
&&& \text{If } S_{\text{Verify}} = 0, \text{reject.}\\
\\
\text{Server sends to Bob} &: S, PK_{\text{Alice}}\\
\\
\text{Bob calculates:}\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Alice}}}(S, PK_{\text{Alice}})
&& \text{Verify message is from Alice.}\\
&&& \text{If } S_{\text{Verify}} = 0, \text{reject.}\\
\end{align*}
$$

## Bob sends message to Alice

$$
\text{Bob sends a given message } M \text{ to Alice}.
$$
$$
\begin{align*}
\text{Bob has} &: SS_{\text{Bob}}, PK_{\text{Alice}}, N\\
\text{Server has} &: PS_{\text{Bob}}, T_{\text{Threshold}}, B, N\\
\text{Alice has} &: SK_{\text{Alice}}, PS_{\text{Bob}}, T_{\text{Threshold}}, B, N\\
\end{align*}
$$
$$
\begin{align*}
\text{Bob calculates} &:\\
K &= \{0, 1\}^{n}
&& \text{Generates key of length } n \text{.}\\
C_{K} &= \text{KEM}_{PK_{\text{Alice}}}(K)
&& \text{Encrypts key.}\\
C_{M} &= \text{Enc}_{K}(M)
&& \text{Encrypts message.}\\
T &= \text{Now}()
&& \text{Get current timestamp.}
\\
n &= \{0,1\}^{128} \text{ s.t. } (n, PS_{\text{Bob}}) \notin N
&& \text{Generate nonce.}\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add nonce to list.}\\
S &= \text{Sign}_{SS_{\text{Bob}}}(T||n||C_{K}||C_{M})
&& \text{Sign message.}\\
\\
\text{Bob sends to server} &: S, T, n, C_{K}, C_{M}\\
\\
\text{Server calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Bob}}}(S, T||n||C_{K}||C_{M})
&& \text{Verify message is from Bob.}\\
&&& \text{If } S_{\text{Verify}} = 0 \text{, reject.}\\
T &> \text{Now}() - T_{\text{Threshold}}
&& \text{Verify message is recent.}
\\
(n, PS_{\text{Bob}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add old nonce to list.}
\\
(PS_{\text{Bob}}, PS_{\text{Alice}}) &\in B
&& \text{Verify Bob can message Alice.}
\\
\\
\end{align*}
$$
$$
\begin{align*}
\text{Server sends to Alice} &: S, T,n, C_{K}, C_{M}\\
\\
\text{Alice calculates} &:\\
S_{\text{Verify}} &= \text{Sign}^{-1}_{PS_{\text{Bob}}}(S, T||n||C_{K}||C_{M})
&& \text{Verify message is from Bob.}\\
&&& \text{If } S_{\text{Verify}} = 0 \text{, reject.}\\
T &> \text{Now}() - T_{\text{Threshold}}
&& \text{Verify message is recent.}
\\
(n, PS_{\text{Bob}}) & \notin N
&& \text{Verify nonce is new.}
\\
N &= N \cup \{(n, PS_{\text{Bob}})\}
&& \text{Add old nonce to list.}
\\
(PS_{\text{Bob}}, PS_{\text{Alice}}) &\in B
&& \text{Verify Bob can message Alice.}
\\
K &= \text{KEM}^{-1}_{SK_{\text{Alice}}}(C_{K})
&& \text{Decrypt key.}\\
M &= \text{Enc}^{-1}_{K}(C_{M})
&& \text{Decrypt message.}
\end{align*}
$$


