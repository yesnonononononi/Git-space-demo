<<<<<<< HEAD
# HashMap源码解析

---

### 变量

- __serialVersionUID__ : 有关于序列化

- __DEFAULT_INITIAL_CAPACITY__ = 16: 默认容量,必须是2的幂

- __MAXIMUM_CAPACITY__ = 1<<30 = 2^30: 最大容量,必须是2的幂

- __DEFAULT_LOAS_FACTOR__ =0,75f: 扩容因子

- __TREEIFY_THRESHOLD__ = 8:树化阈值

- __UNTREEIFY_THRESHOLD__ =6:去树化

- __MIN_TREEIFY_CAPACITY__= 64:树化应达到的最小数组长度 

- `table`:   Node<K,V>[] :核心变量之一,节点数组

- `entrySet`:Set<Map.Entry<K,V>> :一个放着每个键值对的Set集合

- `size` :核心变量之一,数组长度

- `modCount`:操作的次数

- `threshold`:核心变量之一,数组扩容阈值

- `loadFactor`:哈希表的负载系数

---
```java
static final int DEFAULT_INITIAL_CAPACITY = 1 << 4;
```

| 为什么必须是2的幂? | 1<<4 | 如果不是2的幂会怎样?|
| ------------------ | ---- |-------------------|
| 这是由于存储位置`index = (n-1)&hash`计算而得,2的幂-1就会得到二进制全为1的结果,此时,`index == hash % n` (n为数组长度),位运算的效率远高于取模运算 | 2^4=16 |如果不是2的幂,则二进制结果中会有0的假如,这会导致哈希值的某些位无法得到&运算,增加哈希冲突概率|

---

```java
// 这是一个节点,准确来说作用于链表,为HashMap的静态内部类
static class Node<K,V> implements Map.Entry<K,V> { //Entry其实是指一个键值对对象
        final int hash; //哈希值
        final K key;  
        V value;
        Node<K,V> next; //下一个节点Node对象的地址引用

        Node(int hash, K key, V value, Node<K,V> next) {
            this.hash = hash;
            this.key = key;
            this.value = value;
            this.next = next;
        }

        public final K getKey()        { return key; }
        public final V getValue()      { return value; }
        public final String toString() { return key + "=" + value; }

        public final int hashCode() {
            return Objects.hashCode(key) ^ Objects.hashCode(value);
        }
		//修改当前节点的值,这个方法会返回旧的值,设置新的值
        public final V setValue(V newValue) {
            V oldValue = value;
            value = newValue;
            return oldValue;
        }
//此方法用于比较键值对是否相同
        public final boolean equals(Object o) {
            if (o == this)  //这个this大概率是hashmap或者是Entry对象(因为内部类Node继承了Entry接口,比较两个HashMap对象的地址值
                return true;
//如果地址值不一样,
            return o instanceof Map.Entry<?, ?> e  //判断要比较的对象是否是键值对
                    && Objects.equals(key, e.getKey())  //Objects.equals方法会进行深比较,比较键
                    && Objects.equals(value, e.getValue());//比较值
        }
    }
```

---
### 前置方法 ###
---

```java
    //此方法是对键的哈希做了优化
static final int hash(Object key) {
        int h;
    //如果键为空,则哈希值为0,否则会重新计算哈希值,与h>>>16(相当于取哈希值的高位即在前16位补0)做异或运算(相同为1),这会混合高位与低位,从而让低位更加随机,减少哈希冲突
        return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
    }
```

__解析__

通常来说,hashmap会通过哈希值计算key在数组中的位置,但是默认情况下,key的哈希值分布不均,容易导致多个key落在数组的同一个位置,从而引发哈希冲突,但是,由于当数组长度较小的时候,计算位置时只用到哈希值的低四位,假设两个值的哈希差异只会出现在高位,那么这个时候就会导致哈希值强相等的概率非常大,所以这个方法是用来解决这个问题的

---

```java

static Class<?> comparableClassFor(Object x) {
     //检查当前参数是否是可以进行比较的类型,如果不是,返回null
        if (x instanceof Comparable) {
            Class<?> c; Type[] ts, as; ParameterizedType p;
            //如果当前传入参数是字符串,将返回字节码对象
            if ((c = x.getClass()) == String.class) // bypass checks
                return c;
            //如果当前对象(x)实现了接口,则会遍历出所有接口
            if ((ts = c.getGenericInterfaces()) != null) {
                for (Type t : ts) {
                    //如果接口属于带有泛型,泛型的原始类型就是Comparable类型,泛型的实际类型只有一个且为传入参数的类型,返回x的字节码对象
                    if ((t instanceof ParameterizedType) &&
                        ((p = (ParameterizedType) t).getRawType() ==
                         Comparable.class) &&
                        (as = p.getActualTypeArguments()) != null &&
                        as.length == 1 && as[0] == c) // type arg is c
                        return c;
                }
            }
        }
        return null;
    }
```

__方法__

`getGenericInterfaces`: 获取当前字节码对象实现的所有接口字节码对象,返回Type类型的数组

`getRawType`:反射获取泛型,不包括<> ,如List<?>,返回`List.class`

`getActualTypeArguments`: 反射获取实际泛型,如List<String>,返回`String.class`

__目的__

此方法为获取传入参数的字节码对象, 意在检测当前参数对象是否实现了`Comparable`接口(因为`compareTo`方法的调用必须实现`Comparable`接口),保证`compareTo`方法的合理使用

---

```java

static int compareComparables(Class<?> kc, Object k, Object x) {
        return (x == null || x.getClass() != kc ? 0 :
                ((Comparable)k).compareTo(x));
    }
```

__总结__

这是一个比较两个对象的方法,比较规则依据k的被实例类重写的`compareTo`方法规则;如果x不为null且

x的类型与kc相等则进行比较,否则返回0

---

```java
static final int tableSizeFor(int cap) {
    int n = -1 >>> Integer.numberOfLeadingZeros(cap - 1);
    return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

__解析__

方法: `numberOfLeadingZeros`: 获取参数二进制的前导0的个数

作用: 计算当前cap的最小2的幂(即应该初始化的容量),如`cap=3`结果为`4`(因为4为2^2),`cap=7`,结果为8

`cap-1`确保当前参数不是2的幂(如果是二的幂,多算一次),获取前导0个数,与-1(二进制全为1)无符号右移,得到`一个全1二进制数`,这个__全一二进制数的十进制+1就是cap的最小程度最大2的幂__,此时`n=最小幂-1`如果n大于数组最大容量(2^30),则返回最大容量,否则执行n+1(这会获得最小幂),`n<0`防止极端情况默认容量为1

---

### 构造器 ###

---

```java
//注意,这里初始容量即第一个参数,可以是自己传的   
public HashMap(int initialCapacity, float loadFactor) {
        //判断初始容量是否小于零,为真抛出参数异常错误
        if (initialCapacity < 0)
            throw new IllegalArgumentException("Illegal initial capacity: " +
                                               initialCapacity);
        //判断初始参数是否大于最大容量(2^30)为真设置为最大值
        if (initialCapacity > MAXIMUM_CAPACITY)
            initialCapacity = MAXIMUM_CAPACITY;
        //判断当前负载系数是否有效
        if (loadFactor <= 0 || Float.isNaN(loadFactor))
            throw new IllegalArgumentException("Illegal load factor: " +
                                               loadFactor);
        //如果参数全部正确且有意义,则进行初始化构造,
        this.loadFactor = loadFactor;
        this.threshold = tableSizeFor(initialCapacity);//tableSizeFor前面已经说明了,这里为返回大于初始容量的最小二次幂
    }
```

__方法解析__:

`float.NaN()`:判断一个float值是否为非数字,首先`NaN`是float或者double中的一种特殊类型值,可以理解为无意义,比如对负数开根,所以这个方法实际上就是判断传入的`loadFactor`(负载系数)是否是无意义的

__方法作用__ :

初始化负载系数和数组容量,对构造参数进行纠正

---

```java
//使用默认负载系数(0,75f),自定义初始容量的有参构造
public HashMap(int initialCapacity) {
        this(initialCapacity, DEFAULT_LOAD_FACTOR);
    }
```

```java
//无参构造,构造默认负载系数
public HashMap() {
        this.loadFactor = DEFAULT_LOAD_FACTOR; // all other fields defaulted
    }
```

```java
//如果实例化HashMap时,使用了有参构造(需要插入一个Map集合),则会触发,目的是为了腾空间
public HashMap(Map<? extends K, ? extends V> m) {
        this.loadFactor = DEFAULT_LOAD_FACTOR;
        putMapEntries(m, false);
    }
```

---

```java
final void putMapEntries(Map<? extends K, ? extends V> m, boolean evict) {
    //获取参数Map的长度
        int s = m.size();
        if (s > 0) {
            //如果当前数组为空,且参数map有值,扩容参数map的1/4为当前数组长度,如果当前数组不为空,则会循环扩容参数map的长度,直到它的长度小于阈值或者当前数组要达到最大容量
            if (table == null) { // pre-size
                double dt = Math.ceil(s / (double)loadFactor);
                //判断扩容后的数组长度是否超出最大长度(2^30),如果超出,则当前长度为最大容量
                int t = ((dt < (double)MAXIMUM_CAPACITY) ?
                         (int)dt : MAXIMUM_CAPACITY);
                //如果当前长度大于临界值,则将临界值扩大为大于它的最小二次幂
                if (t > threshold)
                    threshold = tableSizeFor(t);
            } else {
                // Because of linked-list bucket constraints, we cannot
                // expand all at once, but can reduce total resize
                // effort by repeated doubling now vs later
                while (s > threshold && table.length < MAXIMUM_CAPACITY)
                    resize();
            }
//获取每一个键值对的键和值,将键hash之后一起传入putVal方法之中
            for (Map.Entry<? extends K, ? extends V> e : m.entrySet()) {
                K key = e.getKey();
                V value = e.getValue();
                putVal(hash(key), key, value, false, evict);
            }
        }
    }

```

__作用__

实现Map接口的putAll方法和Map的构造器

__注意__
这里有个很关键的参数`threshold`(阈值),它是数组扩容的关键参考,当数组`table`未初始化时,即`table=null`,值为`tableSizeFor`的结果,即最小二次幂 

当数组已经初始化了,批量插入键值对时,如果m.size>阈值,达到扩容条件,这时会循环调用`resize`方法,不断扩容`table`的长度,直到阈值大于`m.size`或者达到`table`长度最大值停止

总而言之,这一切的目的就是为批量插入Entry键值对腾空间

---

### 实体方法 ###

---

```java
//提供获取集合长度的getter方法
public int size() {
        return size;
    }
```

```java
//判断集合是否为空的方法
public boolean isEmpty() {
        return size == 0;
    }
```

```java
//从Node[]table中获取值为key的元素,如果有则返回,否则为null
public V get(Object key) {
        Node<K,V> e;
        return (e = getNode(key)) == null ? null : e.value;
    }
```

---

```java
    final Node<K,V> getNode(Object key) {
        Node<K,V>[] tab; Node<K,V> first, e; int n, hash; K k;
        //判断当前数组是否为空,长度是否>0,当前参数key是否可能在table(当前数组)中
        if ((tab = table) != null && (n = tab.length) > 0 &&
            (first = tab[(n - 1) & (hash = hash(key))]) != null) {
            //此时,key有可能在table中(因为table对应的索引有值),判断索引对应的值的哈希以及key的地址,值是否相同
            if (first.hash == hash && // always check first node
                ((k = first.key) == key || (key != null && key.equals(k))))
                //此时,确定key在table中的位置,返回Node节点
                return first;
            //此时,table索引位置存在值,但是不是参数key的值,判断当前节点是否是树节点,即是否树化,如果为真,返回从树中查找的结果
            if ((e = first.next) != null) {
                if (first instanceof TreeNode)
                    return ((TreeNode<K,V>)first).getTreeNode(hash, key);
      //此时,索引位置存在值,但不是key,也不是树节点,那只能是链表节点了;当前,判断下一个节点的hash值,地址,实际值是否等于当前key的hash,地址,实际值
                do {
                    if (e.hash == hash &&
                        ((k = e.key) == key || (key != null && key.equals(k))))
                        //此时,确定下一个节点就是key,返回table索引位置节点的下一个节点
                        return e;
                    //不确定的话,遍历链表
                } while ((e = e.next) != null);
            }
        }
        //不存在,返回null
        return null;
    }
```

__作用__

根据key查找table中是否有key,如果有,则返回

__解析__

* 为什么先判断树,而不是链表?

  答: 这是因为判断树,如果为`false`,就一定是链表了(因为前置已确定不在数组中);否则会多判断一次.注意,链表的形成条件,一定是哈希碰撞发生
---

```java  
 public boolean containsKey(Object key) {
        return getNode(key) != null;
    }


public V put(K key, V value) {
        return putVal(hash(key), key, value, false, true);
    }
```

__作用__

* `containsKey`:判断是否存在key

* `put`:添加键值对到`table`中,`putVal`方法之后再说

---

=======
# HashMap源码解析

---

### 变量

- __serialVersionUID__ : 有关于序列化

- __DEFAULT_INITIAL_CAPACITY__ = 16: 默认容量,必须是2的幂

- __MAXIMUM_CAPACITY__ = 1<<30 = 2^30: 最大容量,必须是2的幂

- __DEFAULT_LOAS_FACTOR__ =0,75f: 扩容因子

- __TREEIFY_THRESHOLD__ = 8:树化阈值

- __UNTREEIFY_THRESHOLD__ =6:去树化

- __MIN_TREEIFY_CAPACITY__= 64:树化应达到的最小数组长度 

- `table`:   Node<K,V>[] :核心变量之一,节点数组

- `entrySet`:Set<Map.Entry<K,V>> :一个放着每个键值对的Set集合

- `size` :核心变量之一,数组长度

- `modCount`:操作的次数

- `threshold`:核心变量之一,数组扩容阈值

- `loadFactor`:哈希表的负载系数

---
```java
static final int DEFAULT_INITIAL_CAPACITY = 1 << 4;
```

| 为什么必须是2的幂? | 1<<4 | 如果不是2的幂会怎样?|
| ------------------ | ---- |-------------------|
| 这是由于存储位置`index = (n-1)&hash`计算而得,2的幂-1就会得到二进制全为1的结果,此时,`index == hash % n` (n为数组长度),位运算的效率远高于取模运算 | 2^4=16 |如果不是2的幂,则二进制结果中会有0的假如,这会导致哈希值的某些位无法得到&运算,增加哈希冲突概率|

---

```java
// 这是一个节点,准确来说作用于链表,为HashMap的静态内部类
static class Node<K,V> implements Map.Entry<K,V> { //Entry其实是指一个键值对对象
        final int hash; //哈希值
        final K key;  
        V value;
        Node<K,V> next; //下一个节点Node对象的地址引用

        Node(int hash, K key, V value, Node<K,V> next) {
            this.hash = hash;
            this.key = key;
            this.value = value;
            this.next = next;
        }

        public final K getKey()        { return key; }
        public final V getValue()      { return value; }
        public final String toString() { return key + "=" + value; }

        public final int hashCode() {
            return Objects.hashCode(key) ^ Objects.hashCode(value);
        }
		//修改当前节点的值,这个方法会返回旧的值,设置新的值
        public final V setValue(V newValue) {
            V oldValue = value;
            value = newValue;
            return oldValue;
        }
//此方法用于比较键值对是否相同
        public final boolean equals(Object o) {
            if (o == this)  //这个this大概率是hashmap或者是Entry对象(因为内部类Node继承了Entry接口,比较两个HashMap对象的地址值
                return true;
//如果地址值不一样,
            return o instanceof Map.Entry<?, ?> e  //判断要比较的对象是否是键值对
                    && Objects.equals(key, e.getKey())  //Objects.equals方法会进行深比较,比较键
                    && Objects.equals(value, e.getValue());//比较值
        }
    }
```

---
### 前置方法 ###
---

```java
    //此方法是对键的哈希做了优化
static final int hash(Object key) {
        int h;
    //如果键为空,则哈希值为0,否则会重新计算哈希值,与h>>>16(相当于取哈希值的高位即在前16位补0)做异或运算(相同为1),这会混合高位与低位,从而让低位更加随机,减少哈希冲突
        return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
    }
```

__解析__

通常来说,hashmap会通过哈希值计算key在数组中的位置,但是默认情况下,key的哈希值分布不均,容易导致多个key落在数组的同一个位置,从而引发哈希冲突,但是,由于当数组长度较小的时候,计算位置时只用到哈希值的低四位,假设两个值的哈希差异只会出现在高位,那么这个时候就会导致哈希值强相等的概率非常大,所以这个方法是用来解决这个问题的

---

```java

static Class<?> comparableClassFor(Object x) {
     //检查当前参数是否是可以进行比较的类型,如果不是,返回null
        if (x instanceof Comparable) {
            Class<?> c; Type[] ts, as; ParameterizedType p;
            //如果当前传入参数是字符串,将返回字节码对象
            if ((c = x.getClass()) == String.class) // bypass checks
                return c;
            //如果当前对象(x)实现了接口,则会遍历出所有接口
            if ((ts = c.getGenericInterfaces()) != null) {
                for (Type t : ts) {
                    //如果接口属于带有泛型,泛型的原始类型就是Comparable类型,泛型的实际类型只有一个且为传入参数的类型,返回x的字节码对象
                    if ((t instanceof ParameterizedType) &&
                        ((p = (ParameterizedType) t).getRawType() ==
                         Comparable.class) &&
                        (as = p.getActualTypeArguments()) != null &&
                        as.length == 1 && as[0] == c) // type arg is c
                        return c;
                }
            }
        }
        return null;
    }
```

__方法__

`getGenericInterfaces`: 获取当前字节码对象实现的所有接口字节码对象,返回Type类型的数组

`getRawType`:反射获取泛型,不包括<> ,如List<?>,返回`List.class`

`getActualTypeArguments`: 反射获取实际泛型,如List<String>,返回`String.class`

__目的__

此方法为获取传入参数的字节码对象, 意在检测当前参数对象是否实现了`Comparable`接口(因为`compareTo`方法的调用必须实现`Comparable`接口),保证`compareTo`方法的合理使用

---

```java

static int compareComparables(Class<?> kc, Object k, Object x) {
        return (x == null || x.getClass() != kc ? 0 :
                ((Comparable)k).compareTo(x));
    }
```

__总结__

这是一个比较两个对象的方法,比较规则依据k的被实例类重写的`compareTo`方法规则;如果x不为null且

x的类型与kc相等则进行比较,否则返回0

---

```java
static final int tableSizeFor(int cap) {
    int n = -1 >>> Integer.numberOfLeadingZeros(cap - 1);
    return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

__解析__

方法: `numberOfLeadingZeros`: 获取参数二进制的前导0的个数

作用: 计算当前cap的最小2的幂(即应该初始化的容量),如`cap=3`结果为`4`(因为4为2^2),`cap=7`,结果为8

`cap-1`确保当前参数不是2的幂(如果是二的幂,多算一次),获取前导0个数,与-1(二进制全为1)无符号右移,得到`一个全1二进制数`,这个__全一二进制数的十进制+1就是cap的最小程度最大2的幂__,此时`n=最小幂-1`如果n大于数组最大容量(2^30),则返回最大容量,否则执行n+1(这会获得最小幂),`n<0`防止极端情况默认容量为1

---

### 构造器 ###

---

```java
//注意,这里初始容量即第一个参数,可以是自己传的   
public HashMap(int initialCapacity, float loadFactor) {
        //判断初始容量是否小于零,为真抛出参数异常错误
        if (initialCapacity < 0)
            throw new IllegalArgumentException("Illegal initial capacity: " +
                                               initialCapacity);
        //判断初始参数是否大于最大容量(2^30)为真设置为最大值
        if (initialCapacity > MAXIMUM_CAPACITY)
            initialCapacity = MAXIMUM_CAPACITY;
        //判断当前负载系数是否有效
        if (loadFactor <= 0 || Float.isNaN(loadFactor))
            throw new IllegalArgumentException("Illegal load factor: " +
                                               loadFactor);
        //如果参数全部正确且有意义,则进行初始化构造,
        this.loadFactor = loadFactor;
        this.threshold = tableSizeFor(initialCapacity);//tableSizeFor前面已经说明了,这里为返回大于初始容量的最小二次幂
    }
```

__方法解析__:

`float.NaN()`:判断一个float值是否为非数字,首先`NaN`是float或者double中的一种特殊类型值,可以理解为无意义,比如对负数开根,所以这个方法实际上就是判断传入的`loadFactor`(负载系数)是否是无意义的

__方法作用__ :

初始化负载系数和数组容量,对构造参数进行纠正

---

```java
//使用默认负载系数(0,75f),自定义初始容量的有参构造
public HashMap(int initialCapacity) {
        this(initialCapacity, DEFAULT_LOAD_FACTOR);
    }
```

```java
//无参构造,构造默认负载系数
public HashMap() {
        this.loadFactor = DEFAULT_LOAD_FACTOR; // all other fields defaulted
    }
```

```java
//如果实例化HashMap时,使用了有参构造(需要插入一个Map集合),则会触发,目的是为了腾空间
public HashMap(Map<? extends K, ? extends V> m) {
        this.loadFactor = DEFAULT_LOAD_FACTOR;
        putMapEntries(m, false);
    }
```

---

```java
final void putMapEntries(Map<? extends K, ? extends V> m, boolean evict) {
    //获取参数Map的长度
        int s = m.size();
        if (s > 0) {
            //如果当前数组为空,且参数map有值,扩容参数map的1/4为当前数组长度,如果当前数组不为空,则会循环扩容参数map的长度,直到它的长度小于阈值或者当前数组要达到最大容量
            if (table == null) { // pre-size
                double dt = Math.ceil(s / (double)loadFactor);
                //判断扩容后的数组长度是否超出最大长度(2^30),如果超出,则当前长度为最大容量
                int t = ((dt < (double)MAXIMUM_CAPACITY) ?
                         (int)dt : MAXIMUM_CAPACITY);
                //如果当前长度大于临界值,则将临界值扩大为大于它的最小二次幂
                if (t > threshold)
                    threshold = tableSizeFor(t);
            } else {
                // Because of linked-list bucket constraints, we cannot
                // expand all at once, but can reduce total resize
                // effort by repeated doubling now vs later
                while (s > threshold && table.length < MAXIMUM_CAPACITY)
                    resize();
            }
//获取每一个键值对的键和值,将键hash之后一起传入putVal方法之中
            for (Map.Entry<? extends K, ? extends V> e : m.entrySet()) {
                K key = e.getKey();
                V value = e.getValue();
                putVal(hash(key), key, value, false, evict);
            }
        }
    }

```

__作用__

实现Map接口的putAll方法和Map的构造器

__注意__
这里有个很关键的参数`threshold`(阈值),它是数组扩容的关键参考,当数组`table`未初始化时,即`table=null`,值为`tableSizeFor`的结果,即最小二次幂 

当数组已经初始化了,批量插入键值对时,如果m.size>阈值,达到扩容条件,这时会循环调用`resize`方法,不断扩容`table`的长度,直到阈值大于`m.size`或者达到`table`长度最大值停止

总而言之,这一切的目的就是为批量插入Entry键值对腾空间

---

### 实体方法 ###

---

```java
//提供获取集合长度的getter方法
public int size() {
        return size;
    }
```

```java
//判断集合是否为空的方法
public boolean isEmpty() {
        return size == 0;
    }
```

```java
//从Node[]table中获取值为key的元素,如果有则返回,否则为null
public V get(Object key) {
        Node<K,V> e;
        return (e = getNode(key)) == null ? null : e.value;
    }
```

---

```java
    final Node<K,V> getNode(Object key) {
        Node<K,V>[] tab; Node<K,V> first, e; int n, hash; K k;
        //判断当前数组是否为空,长度是否>0,当前参数key是否可能在table(当前数组)中
        if ((tab = table) != null && (n = tab.length) > 0 &&
            (first = tab[(n - 1) & (hash = hash(key))]) != null) {
            //此时,key有可能在table中(因为table对应的索引有值),判断索引对应的值的哈希以及key的地址,值是否相同
            if (first.hash == hash && // always check first node
                ((k = first.key) == key || (key != null && key.equals(k))))
                //此时,确定key在table中的位置,返回Node节点
                return first;
            //此时,table索引位置存在值,但是不是参数key的值,判断当前节点是否是树节点,即是否树化,如果为真,返回从树中查找的结果
            if ((e = first.next) != null) {
                if (first instanceof TreeNode)
                    return ((TreeNode<K,V>)first).getTreeNode(hash, key);
      //此时,索引位置存在值,但不是key,也不是树节点,那只能是链表节点了;当前,判断下一个节点的hash值,地址,实际值是否等于当前key的hash,地址,实际值
                do {
                    if (e.hash == hash &&
                        ((k = e.key) == key || (key != null && key.equals(k))))
                        //此时,确定下一个节点就是key,返回table索引位置节点的下一个节点
                        return e;
                    //不确定的话,遍历链表
                } while ((e = e.next) != null);
            }
        }
        //不存在,返回null
        return null;
    }
```

__作用__

根据key查找table中是否有key,如果有,则返回

__解析__

* 为什么先判断树,而不是链表?

  答: 这是因为判断树,如果为`false`,就一定是链表了(因为前置已确定不在数组中);否则会多判断一次.注意,链表的形成条件,一定是哈希碰撞发生
---

```java  
 public boolean containsKey(Object key) {
        return getNode(key) != null;
    }


public V put(K key, V value) {
        return putVal(hash(key), key, value, false, true);
    }
```

__作用__

* `containsKey`:判断是否存在key

* `put`:添加键值对到`table`中,`putVal`方法之后再说

---

>>>>>>> 8d9249b1e7816458c272398511cefa1d1d4ce338
