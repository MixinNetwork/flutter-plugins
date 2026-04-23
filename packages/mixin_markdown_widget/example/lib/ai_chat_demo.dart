import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

class AIChatDemoPage extends StatefulWidget {
  const AIChatDemoPage({super.key});

  @override
  State<AIChatDemoPage> createState() => _AIChatDemoPageState();
}

class _AIChatDemoPageState extends State<AIChatDemoPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _prePopulateMessages();
  }

  void _prePopulateMessages() {
    final random = Random();
    // Pre-populate 20 messages (20 pairs) from the rich 5 presets.
    for (var i = 0; i < 20; i++) {
      _messages.add(ChatMessage.static(
        text: 'Detailed Inquiry regarding technical specification #${i + 1}',
        isUser: true,
      ));
      final markdown = _presetMarkdown[random.nextInt(_presetMarkdown.length)];
      _messages.add(ChatMessage.static(
        text: markdown,
        isUser: false,
      ));
    }
  }

  final List<String> _presetMarkdown = [
    r'''# I. Distributed Systems & Consensus Protocols: A Comprehensive Analysis

This document serves as an exhaustive reference for the architectural evolution of distributed consensus, ranging from the foundational FLP impossibility result to modern-day multi-leader Raft implementations.

## 1. The Core Impossibility
The **FLP Impossibility** (Fischer, Lynch, and Paterson) states that in an asynchronous network where even one process might fail, no deterministic algorithm can guarantee consensus.

> "In a purely asynchronous model, there is no way to distinguish a slow process from one that has crashed."
> 
> > This leads to the requirement of either:
> > 1. **Partial Synchrony**: Making assumptions about network bounds.
> > 2. **Non-determinism**: Utilizing randomness to break symmetry.

### 2. Comparison of Modern Consensus Algorithms

| Algorithm | Leader Selection | Quorum Requirement | Typical Use Case | Latency Profile |
| :--- | :--- | :---: | :--- | :--- |
| **Paxos** | Proposer-based | \( (n+1)/2 \) | Low-level storage | Multi-round high latency |
| **Raft** | Heartbeat-based | \( (n+1)/2 \) | Etcd, Consul, Kubernetes | Single-round stable leader |
| **HotStuff** | Rotating Leader | \( 2f+1 \) | Blockchain (Libra/Diem) | Linear complexity \( O(n) \) |
| **Zab** | Epoch-based | Quorum-based | Apache Zookeeper | High throughput batching |

### 3. Deep Dive into the Raft Log Structure
A Raft node's state machine depends on the strictly ordered log. Below is a representation of a log conflict resolution strategy in Rust:

```rust
pub fn resolve_conflict(local_log: &mut Vec<Entry>, leader_entries: Vec<Entry>) -> Result<(), RaftError> {
    for entry in leader_entries {
        let index = entry.index;
        if index < local_log.len() {
            if local_log[index].term != entry.term {
                local_log.truncate(index);
                local_log.push(entry);
                info!("Truncated log due to term mismatch at index {}", index);
            }
        } else {
            local_log.push(entry);
        }
    }
    // Update commit index based on leader's committed value
    Ok(())
}
```

## 4. Mathematical Foundation of Vector Clocks
To establish partial ordering, we utilize Vector Clocks. If we have \( N \) processes, each process \( P_i \) maintains a vector \( V_i \).

$$ V_i[j] = \text{number of events in } P_j \text{ known to } P_i $$

The comparison rule is:
1. \( V \le V' \) iff \( \forall i, V[i] \le V'[i] \)
2. \( V < V' \) iff \( V \le V' \) and \( \exists j, V[j] < V'[j] \)

### 5. Deployment Roadmap
- [x] Provisioning via Terraform
- [x] Initializing mTLS between peers
- [ ] Benchmarking under partitioned network conditions
  - [x] 3-node cluster partition
  - [ ] 5-node cluster partition (Byzantine simulation)

[^1]: Lamport, L. (1998). "The Part-Time Parliament".
[^2]: Ongaro, D., & Ousterhout, J. (2014). "In Search of an Understandable Consensus Algorithm".
''',
    r'''# II. Quantum Computing & Information Theory: The Qubit Frontier

This treatise explores the mathematical landscape of Hilbert Spaces and the practical realization of gate-based quantum circuits.

## 1. State Representation
A single qubit exists as a superposition of the basis states \( |0\rangle \) and \( |1\rangle \).

$$ |\psi\rangle = \alpha |0\rangle + \beta |1\rangle $$

Where the complex amplitudes satisfy the normalization condition:
$$ |\alpha|^2 + |\beta|^2 = 1 $$

### 2. The Universal Gate Set
To perform arbitrary computations, we utilize a universal set of gates, typically consisting of:
*   **Hadamard (H)**: Creates superposition.
*   **CNOT**: Creates entanglement between two qubits.
*   **T-gate**: Provides the necessary non-Clifford rotation.

| Gate | Matrix Representation | Functionality |
| :--- | :---: | :--- |
| **H** | \( \frac{1}{\sqrt{2}}\begin{pmatrix} 1 & 1 \\ 1 & -1 \end{pmatrix} \) | Maps \( |0\rangle \to |+\rangle \) |
| **X** | \( \begin{pmatrix} 0 & 1 \\ 1 & 0 \end{pmatrix} \) | Bit-flip (Quantum NOT) |
| **Z** | \( \begin{pmatrix} 1 & 0 \\ 0 & -1 \end{pmatrix} \) | Phase-flip |

### 3. Entanglement and Bell States
Quantum entanglement allows for correlations that exceed classical limits. A common Bell State is:

$$ |\Phi^+\rangle = \frac{1}{\sqrt{2}} (|00\rangle + |11\rangle) $$

Implementation of Bell State generation in Python (using a hypothetical SDK):

```python
import quantum_sim as qs

def generate_bell_state():
    circuit = qs.Circuit(2)
    # Apply Hadamard to the first qubit
    circuit.h(0)
    # Entangle with the second qubit
    circuit.cnot(0, 1)
    
    # Run on a simulator
    backend = qs.get_backend('statevector_simulator')
    result = backend.run(circuit)
    return result.get_statevector()

# Result: [0.707, 0, 0, 0.707]
```

## 4. Quantum Error Correction (QEC)
Unlike classical bits, qubits are susceptible to:
1.  **Bit Flips** (\( X \)-errors)
2.  **Phase Flips** (\( Z \)-errors)
3.  **Cross-talk** and Decoherence

> "The Surface Code is currently the most promising architecture for fault-tolerant quantum computing due to its high error threshold (approx. 1%)."

- [ ] Implement Steane Code (7-qubit)
- [x] Verify Shor's Code (9-qubit)
- [ ] Research Topological Protection

***

*Document Status: Draft v0.9.3 | Scientific Review Required.*
''',
    r'''# III. Advanced Bioinformatics: Genomic Mapping and Computational Proteomics

An exploration of the algorithmic complexities involved in de novo genome assembly and protein folding simulations.

## 1. Sequence Alignment Algorithms
At the heart of bioinformatics lies the comparison of DNA sequences. We distinguish between global and local alignment.

### Needleman-Wunsch (Global) vs. Smith-Waterman (Local)
The scoring matrix \( H \) is defined as:

$$ H_{i,j} = \max \begin{cases} H_{i-1,j-1} + S(a_i, b_j) \\ H_{i-1,j} - d \\ H_{i,j-1} - d \end{cases} $$

Where:
*   \( S(a_i, b_j) \) is the substitution score.
*   \( d \) is the gap penalty.

### 2. Protein Folding and AlphaFold2
The transition from 1D amino acid sequences to 3D structures is a problem of energy minimization.

```python
class ProteinFolder:
    def __init__(self, sequence: str):
        self.sequence = sequence
        self.amino_acids = ["A", "R", "N", "D", "C", "Q", "E", "G", "H", "I"]

    def calculate_gibbs_free_energy(self, fold: dict) -> float:
        """Calculate the delta G of a specific conformation."""
        energy = 0.0
        # Complex physics-based calculation here
        for bond in fold['bonds']:
            energy += bond.strength * (bond.length - bond.equilibrium_length)**2
        return energy
```

## 3. Genomic Database Schema
A typical bio-database requires high-throughput indexing for billions of base pairs.

| Table Name | Primary Key | Attributes | Volume |
| :--- | :--- | :--- | :--- |
| `sequences` | `seq_id` | `raw_data`, `organism_id`, `quality_score` | 50 TB |
| `annotations` | `anno_id` | `start_pos`, `end_pos`, `gene_name` | 2 TB |
| `taxonomies` | `tax_id` | `genus`, `species`, `parent_tax_id` | 10 GB |

## 4. Deeply Nested Taxonomy Example
- **Eukaryota**
    - **Metazoa**
        - **Chordata**
            - **Mammalia**
                - **Primates**
                    - *Homo sapiens*
                    - *Pan troglodytes* (Chimpanzee)
                - **Rodentia**
                    - *Mus musculus* (House mouse)
    - **Viridiplantae**
        - **Streptophyta**
            - **Magnoliopsida** (Flowering plants)

> "The advent of CRISPR-Cas9 has revolutionized our ability to perform precision genomic edits, essentially allowing us to 'code' life itself."

[^1]: Doudna, J. A., & Charpentier, E. (2014). "The new frontier of genome engineering with CRISPR-Cas9".
''',
    r'''# IV. Cybersecurity & Cryptographic Engineering: Building Hardened Protocols

This specification details the construction of a post-quantum secure transport layer (PQ-TLS) designed for adversarial environments.

## 1. Key Exchange via Kyber
Kyber is a Module Lattice-based Key Encapsulation Mechanism (KEM).

$$ \text{Public Key: } b = As + e \pmod q $$

Where:
*   \( A \) is a random matrix.
*   \( s \) is the secret vector.
*   \( e \) is the error distribution (Gaussian).

### 2. Implementation of a Secure Buffer
To prevent Buffer Overflow and Side-channel attacks, we utilize constant-time comparison and zero-over-write memory management.

```c
#include <stdint.h>
#include <string.h>

/**
 * Constant-time memory comparison to prevent timing attacks.
 */
int secure_memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *_a = a;
    const uint8_t *_b = b;
    uint8_t result = 0;
    for (size_t i = 0; i < n; i++) {
        result |= (_a[i] ^ _b[i]);
    }
    return (result != 0);
}

void zero_sensitive_data(void *p, size_t n) {
    volatile uint8_t *_p = p;
    while (n--) *_p++ = 0;
}
```

## 3. Protocol Frame Structure (Binary Format)

| Byte Offset | Field Name | Type | Description |
| :--- | :--- | :---: | :--- |
| 0 | `Version` | `u8` | Protocol version (current: `0x03`) |
| 1-2 | `Payload Length` | `u16` | Big-endian length of following data |
| 3 | `Frame Type` | `u8` | `0x01` (Handshake), `0x02` (Data), `0x03` (Alert) |
| 4-11 | `Nonce` | `u64` | Monotonically increasing counter |
| 12-N | `Ciphertext` | `bytes` | AEAD Encrypted payload (ChaCha20-Poly1305) |

## 4. Threat Model Analysis
- **Attacker Capability**: MITM with capture-and-hold capabilities.
- **Risk Mitigation**:
    - **Forward Secrecy**: Ephemeral keys are destroyed immediately after session termination.
    - **Identity Binding**: Certificate Transparency logs required for all root anchors.
    - **Rate Limiting**: IP-based throttling at the edge layer.

> "A cryptosystem is only as strong as its weakest implementation. Avoid 'roll-your-own-crypto' at all costs."

- [x] Implement SHA-3 (Keccak)
- [x] Verify Ed25519 signature validation
- [ ] Integrate Dilithium post-quantum signatures
- [ ] Audit zero-knowledge proof (ZKP) module

***
*Classified Document | For Authorized Engineering Personnel Only.*
''',
    r'''# V. The Ultimate Markdown & LaTeX Stress Test Document

This document combines every supported feature into a single, high-complexity rendering benchmark.

## 1. Nested Blockquote Hierarchy with Inline Math
> This is a level 1 quote.
> > Level 2 quote containing a complex formula:
> > $$ \int_a^b \frac{d}{dx} \left( \sum_{i=1}^\infty \frac{x^i}{i!} \right) dx = e^b - e^a $$
> > > Level 3 quote with a task list and code:
> > > - [x] Support deep nesting
> > > - [ ] Performance optimization for large tables
> > > ```javascript
> > > const stressTest = (iterations) => {
> > >   for(let i=0; i<iterations; i++) {
> > >     console.log(`Render iteration: ${i}`);
> > >   }
> > > }
> > > ```

### 2. The Mega Table: Mixed Content Alignment
| Category | Technical Description | Status | Formula / Code |
| :--- | :--- | :---: | :--- |
| **Parsing** | Supports GFM (GitHub Flavored Markdown) with incremental updates. | ✅ | `parser.parse(chunk)` |
| **Math** | Full LaTeX support via KaTeX-style syntax. | 🚀 | \( \sqrt{x^2 + y^2} = z \) |
| **Tables** | Cell-level formatting and varying alignments. | 🎨 | `| A | B |` |
| **Links** | Supports [inline links](https://flutter.dev) and automatic detection. | 🔗 | <https://mixin.dev> |

## 3. Advanced List Structures
1.  **Ordered Item with Code**
    ```python
    print("This code block is inside an ordered list!")
    ```
2.  **Unordered Sub-lists**
    *   Sub-item A
        *   Sub-sub-item A.1
        *   Sub-sub-item A.2
    *   Sub-item B
3.  **Definition Style Lists**
    *   **Term A**: Description of term A.
    *   **Term B**: Description of term B with a footnote[^1].

## 4. Complex Textual Styles
You can use **bold**, *italic*, ***bold-italic***, ~~strikethrough~~, and `inline code` all in the same sentence. 
Additionally, we support `<kbd>Ctrl</kbd> + <kbd>C</kbd>` and `<u>underlined</u>` tags depending on the configuration.

## 5. Media Rendering
![High Res Nature](https://picsum.photos/id/20/1200/400)
*Figure 1: High-resolution banner image testing horizontal scaling and padding.*

***

## 6. Footnotes Reference
[^1]: This is the first footnote, located inside a stress test document.
[^2]: This is the second footnote, testing multiple reference points.

**End of Stress Test.**
'''
  ];

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() {
      _messages.add(ChatMessage.static(
        text: text,
        isUser: true,
      ));
      _isTyping = true;
    });
    _scrollToBottom();
    _simulateAIResponse();
  }

  void _simulateAIResponse() async {
    final random = Random();
    final responseMarkdown =
        _presetMarkdown[random.nextInt(_presetMarkdown.length)];

    final streamController = StreamController<String>();
    final aiMessage = ChatMessage.streaming(
      isUser: false,
      contentStream: streamController.stream,
    );
    setState(() {
      _messages.add(aiMessage);
    });
    _scrollToBottom();

    // Emit chunks to simulate LLM token streaming.
    var offset = 0;
    while (offset < responseMarkdown.length) {
      await Future.delayed(Duration(milliseconds: random.nextInt(30) + 10));
      if (!mounted) break;
      final chunkSize = random.nextInt(8) + 3;
      final end = min(offset + chunkSize, responseMarkdown.length);
      streamController.add(responseMarkdown.substring(offset, end));
      offset = end;
      _scrollToBottom();
    }

    await streamController.close();
    if (mounted) {
      setState(() {
        _isTyping = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced AI Chat Demo'),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _MessageTile(message: _messages[index]);
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('AI is processing massive data...',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey)),
            ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: _handleSubmitted,
                    decoration: const InputDecoration(
                      hintText:
                          'Ask about distributed systems, quantum physics...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _handleSubmitted(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  /// Creates a message whose full text is known up front (user messages and
  /// pre-populated AI messages).
  ChatMessage.static({required this.text, required this.isUser})
      : contentStream = null;

  /// Creates an AI message that will be populated incrementally via a stream.
  ChatMessage.streaming({required this.isUser, required this.contentStream})
      : text = '';

  final String text;
  final bool isUser;

  /// Emits successive text chunks for streaming AI responses; null otherwise.
  final Stream<String>? contentStream;
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  final MarkdownController _controller = MarkdownController();
  StreamSubscription<String>? _streamSub;

  @override
  void initState() {
    super.initState();
    if (!widget.message.isUser) {
      final stream = widget.message.contentStream;
      if (stream != null) {
        // Streaming AI message: subscribe and feed chunks incrementally.
        _streamSub = stream.listen(
          (chunk) => _controller.appendChunk(chunk),
          onDone: () => _controller.commitStream(),
        );
      } else {
        // Pre-populated static message: load all at once.
        _controller.setData(widget.message.text);
      }
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message && !widget.message.isUser) {
      _streamSub?.cancel();
      _streamSub = null;
      final stream = widget.message.contentStream;
      if (stream != null) {
        _controller.clear();
        _streamSub = stream.listen(
          (chunk) => _controller.appendChunk(chunk),
          onDone: () => _controller.commitStream(),
        );
      } else {
        _controller.setData(widget.message.text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = widget.message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const CircleAvatar(
              child: Icon(Icons.terminal_rounded),
            ),
          if (!isUser) const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: isUser
                  ? Text(widget.message.text,
                      style: const TextStyle(fontWeight: FontWeight.w500))
                  : MarkdownWidget(
                      controller: _controller,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      theme: MarkdownThemeData.fallback(context).copyWith(
                        maxContentWidth: double.infinity,
                      ),
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 12),
          if (isUser)
            const CircleAvatar(
              backgroundColor: Colors.blueGrey,
              child: Icon(Icons.account_circle, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
