# HashMap源码解析


## 一、核心变量定义
HashMap的核心变量决定其存储结构、扩容时机与树化策略，是理解底层原理的基础。

| 变量名                 | 类型          | 作用                                  | 默认值       |
|------------------------|---------------|---------------------------------------|--------------|
| DEFAULT_INITIAL_CAPACITY| int           | 默认初始容量（必须是2的幂）           | 16           |
| MAXIMUM_CAPACITY        | int           | 最大容量                              | 2^30         |
| DEFAULT_LOAD_FACTOR     | float         | 默认负载因子（空间与冲突的平衡点）    | 0.75f        |
| TREEIFY_THRESHOLD       | int           | 树化阈值（链表长度≥此值尝试树化）    | 8            |
| UNTREEIFY_THRESHOLD     | int           | 退树化阈值（红黑树节点数≤此值退化）  | 6            |
| MIN_TREEIFY_CAPACITY    | int           | 最小树化容量（数组≥此值才允许树化）  | 64           |
| table                   | Node<K,V>[]   | 哈希表主体数组（桶数组）              | null         |
| size                    | int           | 实际存储的键值对数量                  | 0            |
| threshold               | int           | 扩容阈值（=容量×负载因子）           | 12（初始）   |
| loadFactor              | float         | 负载因子                              | 0.75f        |
| modCount                | int           | 结构修改次数（快速失败机制）          | 0            |


## 二、静态内部类Node<K,V>
Node是HashMap存储键值对的基本单元，构成单向链表结构。

```java
static class Node<K,V> implements Map.Entry<K,V> {
    final int hash;      // 键的二次哈希值（不可变）
    final K key;         // 键（不可变）
    V value;             // 值（可变）
    Node<K,V> next;      // 下一个节点指针（单向链表）

    // 构造方法、getKey()、getValue()、setValue()等方法略
}
```

**核心特点**：
- 仅通过`next`指针实现单向链表，无前驱指针；
- 实现`Map.Entry`接口，支持键值对的获取与修改；
- `hash`与`key`在创建时确定，后续不可修改。


## 三、前置工具方法
### 3.1 hash(Object key)
计算键的二次哈希值，减少哈希碰撞概率。

```java
static final int hash(Object key) {
    int h;
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
```

**设计意图**：
- 对`key.hashCode()`进行“高低位异或”，让高位信息参与哈希计算；
- 解决数组容量较小时，仅低位参与计算导致的碰撞问题；
- `null` key的哈希值固定为0，统一存储在`table[0]`桶。


### 3.2 tableSizeFor(int cap)
计算“大于等于给定容量的最小2的幂”，确保数组容量始终为2的幂。

```java
static final int tableSizeFor(int cap) {
    int n = cap - 1;
    n |= n >>> 1;
    n |= n >>> 2;
    n |= n >>> 4;
    n |= n >>> 8;
    n |= n >>> 16;
    return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

**设计意图**：
- 通过位运算快速计算最小2的幂，避免用循环判断；
- 为后续`(n-1) & hash`的高效下标计算提供基础（2的幂-1二进制全为1）。


## 四、构造方法
HashMap提供4种构造方法，支持灵活初始化容量与负载因子。

### 4.1 无参构造
```java
public HashMap() {
    this.loadFactor = DEFAULT_LOAD_FACTOR; // 仅初始化负载因子，容量延迟初始化
}
```

**特点**：
- 初始容量（16）和阈值（12）延迟到第一次`put`时通过`resize()`初始化；
- 避免创建HashMap后未使用导致的内存浪费。


### 4.2 指定初始容量的构造
```java
public HashMap(int initialCapacity) {
    this(initialCapacity, DEFAULT_LOAD_FACTOR); // 复用指定容量+负载因子的构造
}
```

**注意点**：
- 传入的`initialCapacity`会被`tableSizeFor()`调整为“最小2的幂”；
- 例如传入`initialCapacity=3`，实际初始容量为4。


### 4.3 指定初始容量与负载因子的构造
```java
public HashMap(int initialCapacity, float loadFactor) {
    // 1. 参数校验：初始容量不能<0，负载因子不能≤0或非数字
    if (initialCapacity < 0)
        throw new IllegalArgumentException("Illegal initial capacity: " + initialCapacity);
    if (initialCapacity > MAXIMUM_CAPACITY)
        initialCapacity = MAXIMUM_CAPACITY;
    if (loadFactor <= 0 || Float.isNaN(loadFactor))
        throw new IllegalArgumentException("Illegal load factor: " + loadFactor);
    
    // 2. 初始化负载因子，阈值暂存调整后的初始容量
    this.loadFactor = loadFactor;
    this.threshold = tableSizeFor(initialCapacity);
}
```

**关键逻辑**：
- 此处`threshold`暂存的是“调整后的初始容量”，而非最终阈值；
- 最终阈值在第一次`resize()`时计算（=容量×负载因子）。


### 4.4 基于Map的构造（批量初始化）
```java
public HashMap(Map<? extends K, ? extends V> m) {
    this.loadFactor = DEFAULT_LOAD_FACTOR;
    putMapEntries(m, false); // 批量插入映射关系
}
```

**核心作用**：
- 用于`new HashMap(anotherMap)`场景，批量导入已有Map的键值对；
- 通过`putMapEntries()`确保容量足够容纳所有元素，避免频繁扩容。


## 五、核心方法解析
### 5.1 putMapEntries(Map<? extends K, ? extends V> m, boolean evict)
批量插入映射关系，支撑“基于Map的构造”与`putAll()`方法。

**核心逻辑**：
1. 计算所需容量：根据传入Map的`size`和负载因子，计算“能容纳所有元素的最小容量”；
2. 扩容准备：若当前数组未初始化，则初始化容量与阈值；若已初始化且`size>threshold`，循环`resize()`直到容量足够；
3. 批量插入：遍历传入Map的`entrySet`，调用`putVal()`逐个插入键值对；
4. `evict`参数：给`LinkedHashMap`留扩展点（用于LRU缓存的过期节点删除）。


### 5.2 resize()
初始化或扩容哈希表，是HashMap动态调整容量的核心方法（兼顾初始化与扩容）。

**核心流程**：
1. 计算新容量与新阈值：
    - 已初始化：新容量=旧容量×2，新阈值=旧阈值×2（若未超最大容量）；
    - 未初始化（无参构造首次`put`）：新容量=16，新阈值=16×0.75=12；
    - 未初始化（有参构造首次`put`）：新容量=`threshold`（之前暂存的调整后初始容量），新阈值=新容量×负载因子。
2. 创建新桶数组：容量为新容量，替换原`table`；
3. 迁移旧节点：
    - 单个节点：直接计算新下标放入新数组；
    - 链表节点：根据`e.hash & oldCap`拆分为“低位链表”（下标不变）和“高位链表”（下标=旧下标+旧容量）；
    - 红黑树节点：调用`split()`方法拆分，拆分后节点数≤6则退化为链表。


### 5.3 treeifyBin(Node<K,V>[] tab, int hash)
树化入口方法，负责判断树化条件并准备树化（不直接构建红黑树）。

**核心逻辑**：
1. 树化前提判断：
    - 若数组为`null`或长度<64（MIN_TREEIFY_CAPACITY）：不树化，调用`resize()`扩容（优先通过扩容分散节点）；
    - 若数组长度≥64：继续树化准备。
2. 节点类型转换与双向链表构建：
    - 遍历桶内单向链表，将`Node`转为`TreeNode`（保留`hash`、`key`、`value`）；
    - 补充`prev`指针，构建双向链表（为后续红黑树构建做准备）。
3. 触发红黑树构建：
    - 将双向链表头节点放回数组，调用`TreeNode.treeify(tab)`完成最终树化。


## 六、代解析模块
以下方法尚未解析，解析时建议侧重对应核心要点（无需深入代码细节）：

### 6.1 putVal(int hash, K key, V value, boolean onlyIfAbsent, boolean evict)
- 侧重点1：桶定位逻辑（`(n-1) & hash`的原理）；
- 侧重点2：冲突处理三分支（桶首节点匹配→覆盖value、红黑树→调用`putTreeVal`、链表→尾插+`binCount`计数）；
- 侧重点3：`binCount`如何触发`treeifyBin`（`binCount ≥ 7`时）；
- 侧重点4：`onlyIfAbsent`（是否覆盖已存在的value）与`evict`（`LinkedHashMap`扩展点）的作用；
- 侧重点5：插入后`size>threshold`触发`resize()`的逻辑。


### 6.2 getNode(int hash, Object key)
- 侧重点1：查询完整流程（桶定位→桶首节点匹配→红黑树/链表遍历）；
- 侧重点2：链表查询（O(n)）与红黑树查询（O(logn)）的效率差异；
- 侧重点3：`null` key的查询处理（固定定位`table[0]`）；
- 侧重点4：判断节点匹配的条件（`hash`相等 + `key`地址/`equals`相等）。


### 6.3 removeNode(int hash, Object key, Object value, boolean matchValue, boolean movable)
- 侧重点1：删除完整流程（桶定位→节点匹配→链表/红黑树节点移除）；
- 侧重点2：`matchValue`的作用（是否需要匹配value才删除，默认false）；
- 侧重点3：红黑树删除后的平衡调整与退树化（节点数≤6时退化链表）；
- 侧重点4：`movable`的作用（红黑树删除后是否允许调整根节点，默认true）；
- 侧重点5：删除后`modCount`自增（快速失败机制）。


### 6.4 TreeNode相关核心方法
#### 6.4.1 putTreeVal(HashMap<K,V> map, Node<K,V>[] tab, int hash, K key, V value)
- 侧重点：红黑树插入逻辑（根据`hash`比较确定左右子树，`hash`相同则用`tieBreakOrder`排序）。

#### 6.4.2 removeTreeNode(HashMap<K,V> map, Node<K,V>[] tab, boolean movable)
- 侧重点：红黑树删除逻辑（删除后调用`balanceDeletion`平衡，节点数不足则退化）。

#### 6.4.3 treeify(Node<K,V>[] tab)
- 侧重点：双向链表转红黑树的核心步骤（建立父子关系、触发`balanceInsertion`平衡）。

#### 6.4.4 balanceInsertion/balanceDeletion
- 侧重点：红黑树平衡调整的作用（通过旋转/变色维持近似平衡，无需深入具体旋转代码）。


### 6.5 其他重要方法
#### 6.5.1 containsValue(Object value)
- 侧重点：与`containsKey`的区别（`containsKey`是O(1)/O(logn)，`containsValue`是O(n)）、遍历所有桶查询的逻辑。

#### 6.5.2 keySet()/values()/entrySet()
- 侧重点：返回集合的“视图特性”（修改原Map会同步影响集合，反之亦然）、避免拷贝的内存优化。

#### 6.5.3 afterNodeAccess/afterNodeInsertion/afterNodeRemoval
- 侧重点：回调方法的作用（`LinkedHashMap`重写以维持插入/访问顺序，支撑LRU缓存）。

#### 6.5.4 writeObject/readObject
- 侧重点：序列化策略（仅序列化有效节点，不序列化空桶）、避免冗余数据的设计。

#### 6.5.5 clone()
- 侧重点：浅克隆特性（`table`数组是新的，但节点引用指向原节点，`key`/`value`不克隆）。