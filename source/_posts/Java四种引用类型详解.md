---
title: Java 四种引用类型详解
date: 2026-07-01 10:00:00
tags: [Java, JVM, 面试]
categories: 后端
---

Java 提供了四种引用类型来控制对象与 GC 之间的关系，核心问题是：**一个对象被引用着，GC 能不能回收它？什么时候回收？**

<!-- more -->

---

## 一、四种引用对比

| 引用类型 | GC 回收时机 | 用途 |
|---------|-----------|------|
| **强引用** | 绝不回收 | 正常编码，99% 的场景 |
| **软引用** | 内存不足时回收 | 缓存（如图片缓存） |
| **弱引用** | 下次 GC 就回收 | 避免内存泄漏（如 WeakHashMap） |
| **虚引用** | 任何时候，仅用于跟踪 | 管理堆外内存（如 DirectByteBuffer） |

回收强度降序：**强 → 软 → 弱 → 虚**

---

## 二、强引用（Strong Reference）

最普通的引用，Java 默认就是强引用：

```java
Object obj = new Object();  // obj 是强引用
```

**规则**：只要强引用链还在，GC **永远不会**回收这个对象，哪怕 OOM。

```java
Object obj = new Object();
obj = null;  // 强引用断了 → 下次 GC 可回收
```

---

## 三、软引用（Soft Reference）

**比强引用弱一级**。内存够时不回收，内存不够时 GC 会回收。

```java
// 创建一个软引用指向大对象
SoftReference<byte[]> softRef = new SoftReference<>(new byte[100 * 1024 * 1024]);

// 正常使用
byte[] data = softRef.get();
if (data != null) {
    // 对象还在，直接使用
} else {
    // 对象被 GC 回收了，需要重新加载
    data = loadFromDisk();
    softRef = new SoftReference<>(data);
}
```

**回收时机**：只有当 JVM 判定**堆内存不足**且即将 OOM 时，才回收软引用指向的对象。

**核心用途**：内存敏感的缓存。用完 GC 自己清，不用手动管理。

---

## 四、弱引用（Weak Reference）

**比软引用更弱**。GC 线程扫描到它就回收，不管内存够不够。

```java
WeakReference<Object> weakRef = new WeakReference<>(new Object());

System.out.println(weakRef.get());  // 有值
System.gc();                         // 触发 GC
System.out.println(weakRef.get());  // null — 被回收了
```

### 最重要的应用：WeakHashMap

```java
WeakHashMap<Object, String> map = new WeakHashMap<>();
Object key = new Object();
map.put(key, "value");

System.out.println(map.size());  // 1
key = null;                       // 断开 key 的强引用
System.gc();                      // GC 触发
System.out.println(map.size());  // 0 → key 被回收，entry 自动移除
```

**为什么需要这个？** 普通 HashMap 存了 key 之后即使 key 不再使用，HashMap 自身仍然持有强引用，导致 key 无法被 GC 回收——这就是内存泄漏。WeakHashMap 的 key 是弱引用，当 key 除了 WeakHashMap 内部之外没有其他地方引用时，GC 回收 key 后 entry 被自动清理。

典型场景：类的临时元数据缓存、框架的会话管理。

---

## 五、虚引用（Phantom Reference）

最弱的引用。**`get()` 永远返回 `null`** — 你永远无法通过它拿到对象。

```java
ReferenceQueue<Object> queue = new ReferenceQueue<>();
PhantomReference<Object> phantomRef = new PhantomReference<>(new Object(), queue);

System.out.println(phantomRef.get());  // 永远是 null
```

虚引用存在的唯一目的：当对象被 GC 回收时，**收到一个通知**，用于做资源清理。

### 核心用途：管理堆外内存

Java NIO 允许直接在堆外分配内存，这块内存 GC 管不了。DirectByteBuffer 内部用 Cleaner（基于虚引用实现）来释放堆外内存：

```java
// 简化示意
class DirectByteBuffer {
    private long address;  // 指向堆外内存的指针

    DirectByteBuffer(int capacity) {
        this.address = unsafe.allocateMemory(capacity);  // 堆外 malloc
        Cleaner.create(this, () -> unsafe.freeMemory(address));  // 注册清理回调
    }
}
```

流程：

```
1. DirectByteBuffer 对象在堆内，很小
2. 它持有的 address 指向堆外一大块内存
3. 当 DirectByteBuffer 没有强引用 → GC 回收堆内对象
4. 虚引用被加入 ReferenceQueue
5. ReferenceHandler 线程处理队列 → 调用 freeMemory(address)
6. 堆外内存被释放
```

---

## 六、ReferenceQueue — 回收通知

软引用、弱引用、虚引用都可以绑定一个 `ReferenceQueue`：

```java
ReferenceQueue<Object> queue = new ReferenceQueue<>();
WeakReference<Object> ref = new WeakReference<>(new Object(), queue);

// 当对象被回收后，ref 会自动加入 queue
Reference<?> collected = queue.poll();   // 非阻塞
Reference<?> collected = queue.remove(); // 阻塞等待
```

---

## 七、四种引用关系图

```
强引用:  obj ────→ [对象]   GC: 不回收
软引用:  softRef ─→ [对象]   GC: 内存不够才回收
弱引用:  weakRef ─→ [对象]   GC: 发现即回收
虚引用:  phantom ⇢ [对象]    GC: get() 永远返回 null，回收时发通知
```

---

## 总结

- **强引用**：默认，宁可 OOM 也不回收。所有正常 `new` 出来的变量都是。
- **软引用**：内存紧张时回收。适合做**缓存**，让 GC 帮你管理内存边界。
- **弱引用**：GC 跑就回收。适合**避免内存泄漏**，典型如 WeakHashMap。
- **虚引用**：拿不到对象，纯粹用于**在对象被回收后做资源清理**，典型如管理堆外内存。

**记忆技巧**：强 > 软 > 弱 > 虚，从"死活不让 GC 回收"到"只给 GC 回收发通知"逐级递减。
