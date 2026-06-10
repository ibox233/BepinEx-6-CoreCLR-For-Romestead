#![allow(non_snake_case)]

use std::ffi::{c_char, c_void, CString};
#[cfg(debug_assertions)]
use std::fs::OpenOptions;
#[cfg(debug_assertions)]
use std::io::Write;
use std::iter::once;
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Once;

type Bool = i32;
type Dword = u32;
type Farproc = *mut c_void;
type Hmodule = *mut c_void;
type HostfxrHandle = *mut c_void;
type Lpcstr = *const c_char;
type Lpvoid = *mut c_void;

const DLL_PROCESS_ATTACH: Dword = 1;
const HDT_LOAD_ASSEMBLY_AND_GET_FUNCTION_POINTER: i32 = 5;

static INIT: Once = Once::new();
static BOOTSTRAP: Once = Once::new();
static mut REAL_D3D11: Hmodule = ptr::null_mut();
static mut SELF_MODULE: Hmodule = ptr::null_mut();

#[link(name = "kernel32")]
unsafe extern "system" {
    fn DisableThreadLibraryCalls(hLibModule: Hmodule) -> Bool;
    fn GetModuleFileNameW(hModule: Hmodule, lpFilename: *mut u16, nSize: Dword) -> Dword;
    fn GetProcAddress(hModule: Hmodule, lpProcName: Lpcstr) -> Farproc;
    fn LoadLibraryA(lpLibFileName: Lpcstr) -> Hmodule;
    fn LoadLibraryW(lpLibFileName: *const u16) -> Hmodule;
}

type HostfxrInitializeForRuntimeConfigFn =
    unsafe extern "system" fn(*const u16, *const c_void, *mut HostfxrHandle) -> i32;
type HostfxrGetRuntimeDelegateFn =
    unsafe extern "system" fn(HostfxrHandle, i32, *mut *mut c_void) -> i32;
type HostfxrCloseFn = unsafe extern "system" fn(HostfxrHandle) -> i32;
type LoadAssemblyAndGetFunctionPointerFn = unsafe extern "system" fn(
    *const u16,
    *const u16,
    *const u16,
    *const u16,
    *mut c_void,
    *mut *mut c_void,
) -> i32;
type ComponentEntryPointFn = unsafe extern "system" fn(*mut c_void, i32) -> i32;

#[cfg(debug_assertions)]
fn log_line(line: &str) {
    let path = std::env::temp_dir().join("romestead_d3d11_shim_debug.log");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{}", line);
    }
}

#[cfg(not(debug_assertions))]
fn log_line(_line: &str) {}

unsafe fn init() {
    INIT.call_once(|| unsafe {
        log_line("d3d11 shim initialized");

        let Ok(path) = CString::new("C:\\Windows\\System32\\d3d11.dll") else {
            return;
        };

        REAL_D3D11 = LoadLibraryA(path.as_ptr());
        log_line(&format!("LoadLibraryA real d3d11 => 0x{:x}", REAL_D3D11 as usize));
    });
}

unsafe fn get_proc<T>(module: Hmodule, name: &[u8]) -> Option<T> {
    if module.is_null() {
        return None;
    }

    let proc = unsafe { GetProcAddress(module, name.as_ptr() as Lpcstr) };
    if proc.is_null() {
        log_line(&format!("missing export: {}", String::from_utf8_lossy(&name[..name.len() - 1])));
        None
    } else {
        Some(unsafe { std::mem::transmute_copy(&proc) })
    }
}

unsafe fn get_d3d11_fn<T>(name: &[u8]) -> Option<T> {
    unsafe {
        init();
        get_proc(REAL_D3D11, name)
    }
}

unsafe fn module_dir(module: Hmodule) -> Option<PathBuf> {
    let mut buf = [0u16; 32768];
    let len = unsafe { GetModuleFileNameW(module, buf.as_mut_ptr(), buf.len() as Dword) } as usize;
    if len == 0 || len >= buf.len() {
        return None;
    }

    let path = PathBuf::from(std::ffi::OsString::from_wide(&buf[..len]));
    path.parent().map(Path::to_path_buf)
}

fn wide_path(path: &Path) -> Vec<u16> {
    path.as_os_str().encode_wide().chain(once(0)).collect()
}

fn wide_str(value: &str) -> Vec<u16> {
    std::ffi::OsStr::new(value).encode_wide().chain(once(0)).collect()
}

unsafe fn bootstrap_bepinex() {
    BOOTSTRAP.call_once(|| unsafe {
        log_line("bootstrap begin");

        let Some(game_dir) = module_dir(SELF_MODULE) else {
            log_line("could not determine shim directory");
            return;
        };

        let hostfxr_path = game_dir.join("hostfxr.dll");
        let runtime_config_path = game_dir.join("Romestead.runtimeconfig.json");
        let loader_path = game_dir.join("BepInEx.NET.CoreCLR.dll");

        if !runtime_config_path.exists() || !loader_path.exists() {
            log_line("runtime config or loader is missing");
            return;
        }

        let hostfxr = LoadLibraryW(wide_path(&hostfxr_path).as_ptr());
        log_line(&format!("LoadLibraryW hostfxr => 0x{:x}", hostfxr as usize));
        if hostfxr.is_null() {
            return;
        }

        let Some(initialize_for_runtime_config) =
            get_proc::<HostfxrInitializeForRuntimeConfigFn>(
                hostfxr,
                b"hostfxr_initialize_for_runtime_config\0",
            )
        else {
            return;
        };

        let Some(get_runtime_delegate) =
            get_proc::<HostfxrGetRuntimeDelegateFn>(hostfxr, b"hostfxr_get_runtime_delegate\0")
        else {
            return;
        };

        let close = get_proc::<HostfxrCloseFn>(hostfxr, b"hostfxr_close\0");

        let mut context: HostfxrHandle = ptr::null_mut();
        let rc = initialize_for_runtime_config(
            wide_path(&runtime_config_path).as_ptr(),
            ptr::null(),
            &mut context,
        );
        log_line(&format!("hostfxr_initialize_for_runtime_config => 0x{:x}", rc));

        let delegate_context = if rc < 0 || context.is_null() {
            ptr::null_mut()
        } else {
            context
        };

        let mut load_assembly: *mut c_void = ptr::null_mut();
        let rc = get_runtime_delegate(
            delegate_context,
            HDT_LOAD_ASSEMBLY_AND_GET_FUNCTION_POINTER,
            &mut load_assembly,
        );
        log_line(&format!("hostfxr_get_runtime_delegate => 0x{:x}", rc));

        if !context.is_null() {
            if let Some(close_fn) = close {
                let close_rc = close_fn(context);
                log_line(&format!("hostfxr_close => 0x{:x}", close_rc));
            }
        }

        if rc < 0 || load_assembly.is_null() {
            return;
        }

        let load_assembly: LoadAssemblyAndGetFunctionPointerFn = std::mem::transmute_copy(&load_assembly);
        let assembly_path = wide_path(&loader_path);
        let type_name = wide_str("BepInEx.NET.CoreCLR.NativeEntrypoint, BepInEx.NET.CoreCLR");
        let method_name = wide_str("Initialize");
        let mut entrypoint: *mut c_void = ptr::null_mut();

        let rc = load_assembly(
            assembly_path.as_ptr(),
            type_name.as_ptr(),
            method_name.as_ptr(),
            ptr::null(),
            ptr::null_mut(),
            &mut entrypoint,
        );
        log_line(&format!("load_assembly_and_get_function_pointer => 0x{:x}", rc));
        if rc < 0 || entrypoint.is_null() {
            return;
        }

        let entrypoint: ComponentEntryPointFn = std::mem::transmute_copy(&entrypoint);
        let rc = entrypoint(ptr::null_mut(), 0);
        log_line(&format!("NativeEntrypoint.Initialize => 0x{:x}", rc));
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn DllMain(hinst: Hmodule, reason: Dword, _reserved: Lpvoid) -> Bool {
    if reason == DLL_PROCESS_ATTACH {
        unsafe {
            SELF_MODULE = hinst;
            DisableThreadLibraryCalls(hinst);
        }
    }

    1
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn D3D11CreateDevice(
    pAdapter: *mut c_void,
    DriverType: u32,
    Software: Hmodule,
    Flags: u32,
    pFeatureLevels: *const u32,
    FeatureLevels: u32,
    SDKVersion: u32,
    ppDevice: *mut *mut c_void,
    pFeatureLevel: *mut u32,
    ppImmediateContext: *mut *mut c_void,
) -> i32 {
    type F = extern "system" fn(
        *mut c_void,
        u32,
        Hmodule,
        u32,
        *const u32,
        u32,
        u32,
        *mut *mut c_void,
        *mut u32,
        *mut *mut c_void,
    ) -> i32;

    unsafe {
        bootstrap_bepinex();
        get_d3d11_fn::<F>(b"D3D11CreateDevice\0").map_or(-1, |f| {
            f(
                pAdapter,
                DriverType,
                Software,
                Flags,
                pFeatureLevels,
                FeatureLevels,
                SDKVersion,
                ppDevice,
                pFeatureLevel,
                ppImmediateContext,
            )
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn D3D11CreateDeviceAndSwapChain(
    pAdapter: *mut c_void,
    DriverType: u32,
    Software: Hmodule,
    Flags: u32,
    pFeatureLevels: *const u32,
    FeatureLevels: u32,
    SDKVersion: u32,
    pSwapChainDesc: *const c_void,
    ppSwapChain: *mut *mut c_void,
    ppDevice: *mut *mut c_void,
    pFeatureLevel: *mut u32,
    ppImmediateContext: *mut *mut c_void,
) -> i32 {
    type F = extern "system" fn(
        *mut c_void,
        u32,
        Hmodule,
        u32,
        *const u32,
        u32,
        u32,
        *const c_void,
        *mut *mut c_void,
        *mut *mut c_void,
        *mut u32,
        *mut *mut c_void,
    ) -> i32;

    unsafe {
        bootstrap_bepinex();
        get_d3d11_fn::<F>(b"D3D11CreateDeviceAndSwapChain\0").map_or(-1, |f| {
            f(
                pAdapter,
                DriverType,
                Software,
                Flags,
                pFeatureLevels,
                FeatureLevels,
                SDKVersion,
                pSwapChainDesc,
                ppSwapChain,
                ppDevice,
                pFeatureLevel,
                ppImmediateContext,
            )
        })
    }
}
