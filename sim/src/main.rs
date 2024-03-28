extern crate libz_sys;
use std::ffi::CString;
use std::pin::Pin;
use cxx::UniquePtr;
use indexmap::IndexMap;
use rand::Rng;
use std::collections::VecDeque;
use rand::seq::SliceRandom;

#[cxx::bridge]
#[allow(unused)]
mod ffi {
    unsafe extern "C++" {
        include!("sim/src/lib.hpp");

        type VerilatedContext;
        fn new_context_unique() -> UniquePtr<VerilatedContext>;
    }

    unsafe extern "C++" {
        include!("sim/src/lib.hpp");

        type VerilatedFstC;
        fn new_fstc_unique() -> UniquePtr<VerilatedFstC>;
        #[cxx_name = "open"]
        unsafe fn open_raw(self: Pin<&mut VerilatedFstC>, filename: *const c_char);
        fn dump(self: Pin<&mut VerilatedFstC>, time: u64);
        fn flush(self: Pin<&mut VerilatedFstC>);
    }

    unsafe extern "C++" {
        include!("sim/src/lib.hpp");

        type Vhashmap;

        fn new_vhashmap_unique(ctx: Pin<&mut VerilatedContext>) -> UniquePtr<Vhashmap>;
        fn eval(self: Pin<&mut Vhashmap>);
        #[cxx_name = "trace"]
        unsafe fn trace_raw(self: Pin<&mut Vhashmap>, tfp: *mut VerilatedFstC, levels: i32, options: i32);

        fn set_clk(vhashmap: Pin<&mut Vhashmap>, clk: u8);
        fn set_insert(vhashmap: Pin<&mut Vhashmap>, insert: u8);
        fn get_busy(vhashmap: Pin<&mut Vhashmap>) -> u8;
        fn set_ins_key(vhashmap: Pin<&mut Vhashmap>, ins_key: u32);
        fn set_ins_value(vhashmap: Pin<&mut Vhashmap>, ins_value: u32);
        fn set_lookup(vhashmap: Pin<&mut Vhashmap>, lookup: u8);
        fn set_key(vhashmap: Pin<&mut Vhashmap>, key: u32);
        fn set_modify(vhashmap: Pin<&mut Vhashmap>, modify: u8);
        fn set_del(vhashmap: Pin<&mut Vhashmap>, del: u8);
        fn set_mod_value(vhashmap: Pin<&mut Vhashmap>, mod_value: u32);
        fn get_valid(vhashmap: Pin<&mut Vhashmap>) -> u8;
        fn get_value(vhashmap: Pin<&mut Vhashmap>) -> u32;
    }

    unsafe extern "C++" {
        include!("sim/src/lib.hpp");

        fn trace_ever_on(on: bool);
    }
}

impl ffi::VerilatedContext {
    pub fn new_unique() -> UniquePtr<Self> {
        ffi::new_context_unique()
    }
}

impl ffi::VerilatedFstC {
    pub fn new_unique() -> UniquePtr<Self> {
        ffi::new_fstc_unique()
    }

    pub fn open(self: Pin<&mut Self>, fname: &str) -> std::io::Result<()> {
        let filename = CString::new(fname)?;
        unsafe {self.open_raw(filename.as_ptr())};
        Ok(())
    }
}

impl ffi::Vhashmap {
    pub fn new_unique(ctx: Pin<&mut ffi::VerilatedContext>) -> UniquePtr<Self> {
        ffi::new_vhashmap_unique(ctx)
    }

    pub unsafe fn trace(self: Pin<&mut Self>, tracer: Pin<&mut ffi::VerilatedFstC>, levels: i32, options: i32) {
        let tracer = unsafe {tracer.get_unchecked_mut() as *mut ffi::VerilatedFstC};
        self.trace_raw(tracer, levels, options);
    }
}

const MAX_INSERT: usize = 15000;

fn deterministic_fill_readback(state: &mut usize, vhashmap: &mut UniquePtr<ffi::Vhashmap>) -> bool{

    if *state < MAX_INSERT {

        if (ffi::get_busy(vhashmap.pin_mut()) & 0x1) == 0 {
            ffi::set_insert(vhashmap.pin_mut(), 1);
            ffi::set_ins_key(vhashmap.pin_mut(), (*state).pow(2) as u32);
            ffi::set_ins_value(vhashmap.pin_mut(), *state as u32);

            *state+=1;
        }

    } else {
        ffi::set_insert(vhashmap.pin_mut(), 0);
        ffi::set_key(vhashmap.pin_mut(), (*state - MAX_INSERT).pow(2) as u32);
        ffi::set_lookup(vhashmap.pin_mut(), 1);

        //Check outputs
        if *state >= MAX_INSERT + 2 {
            assert_eq!(1, ffi::get_valid(vhashmap.pin_mut()));
            assert_eq!((*state-2-MAX_INSERT) as u32, ffi::get_value(vhashmap.pin_mut()));
        }

        *state+=1;
    }

    return *state == 2*MAX_INSERT+2;

}

struct RandomizedState {
    filled:  bool,
    ops:     usize,
    map:     IndexMap<u32, u32>,
    lookups: VecDeque<Option<(u32, Option<Option<u32>>)>>,
    recents: VecDeque<u32>,

    //Stats
    num_lookups_checked: usize,
    num_lookups_matched: usize,
    num_modifications:   usize,
    num_deletes:         usize,
    num_idles:           usize,
    num_recents:         usize,
    num_inserts:         usize,
}

impl RandomizedState {
    fn new() -> RandomizedState {
        RandomizedState {
            filled:  false,
            ops:     0,
            map:     IndexMap::new(),
            lookups: VecDeque::new(),
            recents: VecDeque::new(),

            num_lookups_checked: 0,
            num_lookups_matched: 0,
            num_modifications:   0,
            num_deletes:         0,
            num_idles:           0,
            num_recents:         0,
            num_inserts:         0,
        }
    }
}

enum Operation {
    Idle,
    LookupPresent(Option<bool>), //Includes optional modification operation
    LookupAny,                   //Expected not to be present
    LookupRecent,
}

fn choose_recents(recents: &VecDeque<u32>) -> u32{
    assert!(recents.len() != 0);

    let (s0, s1) = recents.as_slices();

    let key = if s0.len() == 0 {
        s1.choose(&mut rand::thread_rng()).unwrap()
    } else if s1.len() == 0 {
        s0.choose(&mut rand::thread_rng()).unwrap()
    } else {
        let slice = if rand::random() {s0} else {s1};
        slice.choose(&mut rand::thread_rng()).unwrap() //TODO: could weight by slice length
    };

    *key
}

fn randomized_operations(state: &mut RandomizedState, vhashmap: &mut UniquePtr<ffi::Vhashmap>) -> bool {
    if !state.filled {

        //Fill it up first
        if (ffi::get_busy(vhashmap.pin_mut()) & 0x1) == 0 {

            let key = loop {
                let key = rand::random::<u32>();
                if !state.map.contains_key(&key) {
                    break key;
                }
            };
            let val = rand::random::<u32>();

            ffi::set_insert(vhashmap.pin_mut(), 1);
            ffi::set_ins_key(vhashmap.pin_mut(), key);
            ffi::set_ins_value(vhashmap.pin_mut(), val);

            state.map.insert(key, val);

            if state.map.len() == MAX_INSERT {
                state.filled = true;
                println!("Finished pre-fill");
            }
        }

        return false;

    } else {

        assert!(state.lookups.len() <= 2);

        /*
         * Check lookup results
         *
         * Also handle modifications and deletions, which take place two cycles after the lookup
         * operation
         */

        //Pin defaults
        ffi::set_del(vhashmap.pin_mut(), 0);
        ffi::set_modify(vhashmap.pin_mut(), 0);
        ffi::set_insert(vhashmap.pin_mut(), 0);
        ffi::set_lookup(vhashmap.pin_mut(), 0);

        //Adjust the queue of recent operations
        while state.recents.len() >= 100 {
            state.recents.pop_front().unwrap();
        }  

        //Check outputs
        if state.lookups.len() == 2 {
            let lu_value = state.lookups.pop_front().unwrap();

            //Check the lookup valid signal is correct
            assert_eq!(lu_value.is_some(), ffi::get_valid(vhashmap.pin_mut()) != 0);
            state.num_lookups_checked += 1;

            if let Some((value, modval)) = lu_value {

                //Check the lookup value is what we expect
                assert_eq!(value,  ffi::get_value(vhashmap.pin_mut()));
                state.num_lookups_matched += 1;

                if let Some(val) = modval {

                    ffi::set_modify(vhashmap.pin_mut(), 1);

                    match val {
                        Some(val) => {
                            ffi::set_mod_value(vhashmap.pin_mut(), val);
                        }
                        None => {
                            ffi::set_del(vhashmap.pin_mut(), 1);
                            state.num_deletes += 1;
                        }
                    }
                    state.num_modifications += 1;
                }
            }
        
        }

        let with_no_recent = vec![
            Operation::Idle,
            Operation::LookupPresent(None), 
            Operation::LookupPresent(Some(false)), 
            Operation::LookupPresent(Some(true)), 
            Operation::LookupAny,
        ];

        let with_recent = vec![
            Operation::Idle,
            Operation::LookupPresent(None), 
            Operation::LookupPresent(Some(false)), 
            Operation::LookupPresent(Some(true)), 
            Operation::LookupAny,
            Operation::LookupRecent,
        ];

        let options = if state.recents.len() != 0 {
            with_recent 
        } else {
            with_no_recent
        };

        //Do some random operations
        match options.choose(&mut rand::thread_rng()).unwrap() {

            Operation::Idle => {
                state.lookups.push_back(None);
                state.num_idles += 1;
            }

            Operation::LookupPresent(do_mod) => {
                ffi::set_lookup(vhashmap.pin_mut(), 1);

                let mut rng = rand::thread_rng();
                let index: usize = rng.gen_range(0..state.map.len());
                let mut ent = state.map.get_index_entry(index).unwrap();

                ffi::set_key(vhashmap.pin_mut(), *ent.key());

                let key     = *ent.key();
                let old_val = *ent.get();

                let modval = if let Some(del) = *do_mod {
                    if del {
                        let _ = ent.swap_remove();
                        Some(None)
                    } else {
                        let new_val = rand::random::<u32>();
                        *(ent.get_mut()) = new_val;
                        Some(Some(new_val))
                    }
                } else {
                    None
                };

                state.lookups.push_back(Some((old_val, modval)));
                state.recents.push_back(key);
            }

            Operation::LookupRecent => {
                ffi::set_lookup(vhashmap.pin_mut(), 1);

                let key = choose_recents(&state.recents);
                let val = state.map.get(&key);

                ffi::set_key(vhashmap.pin_mut(), key);

                let value = match val {
                    Some(val) => {Some((*val, None))},
                    None      => None,
                };

                state.lookups.push_back(value);

                state.num_recents += 1;
            }

            Operation::LookupAny => {
                ffi::set_lookup(vhashmap.pin_mut(), 1);

                let key = rand::random::<u32>();

                ffi::set_key(vhashmap.pin_mut(), key);

                let value = match state.map.get(&key) {
                    Some(val) => Some((*val, None)),
                    None      => None
                };

                state.lookups.push_back(value);
            }

        }

        //Randomly insert if we have fewer than MAX_INSERT vals and arent busy
        //TODO: this is incorrect because things can be inserted before being fully removed by a
        //delete operation
        if state.map.len() < MAX_INSERT {
            if (ffi::get_busy(vhashmap.pin_mut()) & 0x1) == 0 {
                if rand::random() {

                    let key = loop {

                        //let key = if rand::random() {
                        //    rand::random::<u32>()
                        //} else {
                        //    choose_recents(&state.recents)
                        //};
                        let key = rand::random::<u32>();

                        if !state.map.contains_key(&key) {
                            break key;
                        }
                    };

                    let val = rand::random::<u32>();

                    ffi::set_insert(vhashmap.pin_mut(), 1);
                    ffi::set_ins_key(vhashmap.pin_mut(), key);
                    ffi::set_ins_value(vhashmap.pin_mut(), val);

                    state.map.insert(key, val);
                    state.num_inserts += 1;

                    state.recents.push_back(key);
                }
            }
        }

        state.ops += 1;
        return state.ops == 50000;
    }
}

fn main() {
    let mut ctx  = ffi::VerilatedContext::new_unique();
    let mut vhashmap = ffi::Vhashmap::new_unique(ctx.pin_mut());
    let mut fst  = ffi::VerilatedFstC::new_unique();

    unsafe {vhashmap.pin_mut().trace(fst.pin_mut(), 99, 0)};

    ffi::trace_ever_on(true);
    fst.pin_mut().open("dump.fst").unwrap();

    let mut time: u64 = 0;
    let mut state = RandomizedState::new();

    //Is this needed
    ffi::set_clk(vhashmap.pin_mut(), 1);
    vhashmap.pin_mut().eval();
    fst.pin_mut().dump(time);
    time+=1;

    loop {

        ffi::set_clk(vhashmap.pin_mut(), 0);
        vhashmap.pin_mut().eval();
        fst.pin_mut().dump(time);
        time+=1;

        ffi::set_clk(vhashmap.pin_mut(), 1);
        vhashmap.pin_mut().eval();

        let done = randomized_operations(&mut state, &mut vhashmap);
        vhashmap.pin_mut().eval();

        fst.pin_mut().dump(time);
        time+=1;

        fst.pin_mut().flush();

        if done {
            break;
        }
    }

    println!("Num lookups checked: {}", state.num_lookups_checked);
    println!("Num lookups matched: {}", state.num_lookups_matched);
    println!("Num modifications:   {}", state.num_modifications);
    println!("Num deletes:         {}", state.num_deletes);
    println!("Num idles:           {}", state.num_idles);
    println!("Num recents:         {}", state.num_recents);
    println!("Num inserts:         {}", state.num_inserts);
}
