use crate::memory::WordIO;

#[derive(Debug)]
pub struct Heap {
    heap_base: u16,
    heap_end: u16,
    heap_max: u16,
    heap_free: u16,
    alloc_size: u16,
}

impl Heap {
    pub fn new(heap_base: u16, heap_max: u16, alloc_size: u16) -> Heap {
        assert!(heap_base != heap_max);
        assert!(heap_base != u16::max_value());
        assert!(alloc_size >= 2); // So that addresses can be written into the free list
        Heap {
            heap_base,
            heap_end: heap_base,
            heap_max,
            heap_free: 0,
            alloc_size,
        }
    }

    pub fn alloc(&mut self, memory: &WordIO) -> Result<u16, String> {
        if self.heap_end + self.alloc_size <= self.heap_max {
            let addr = self.heap_end;
            self.heap_end += self.alloc_size;
            Ok(addr)
        } else if self.heap_free != 0 {
            let addr = self.heap_free;
            self.heap_free = memory.read_word(self.heap_free)?;
            Ok(addr)
        } else {
            Err("Out of memory".to_string())
        }
    }

    pub fn free(&mut self, memory: &mut WordIO, addr: u16) -> Result<(), String> {
        memory.write_word(addr, self.heap_free)?;
        self.heap_free = addr;
        Ok(())
    }
}

#[cfg(test)]
mod heap_tests {
    use super::Heap;
    use crate::memory::MemoryCell;
    use crate::memory::MEMORY_CELL_SIZE;

    #[test]
    fn alloc_and_free() -> Result<(), String> {
        let mut memory = MemoryCell::default();
        let mut heap = Heap::new(2, MEMORY_CELL_SIZE, 4);
        let mut addrs = Vec::new();
        let mut addr = heap.alloc(&memory);
        while !addr.is_err() {
            addrs.push(addr.unwrap());
            addr = heap.alloc(&memory);
        }
        for addr in addrs {
            heap.free(&mut memory, addr)?;
        }
        let _addr = heap.alloc(&memory)?;
        Ok(())
    }
}
