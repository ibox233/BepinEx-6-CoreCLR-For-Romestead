#![allow(non_snake_case)]

use std::ffi::{c_char, c_void};
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
type Hresult = i32;
type Hmodule = *mut c_void;
type HostfxrHandle = *mut c_void;
type Lpcstr = *const c_char;
type Ntstatus = i32;
type RawArg = usize;
type SizeT = usize;
type Uint = u32;

const E_FAIL: Hresult = 0x80004005u32 as Hresult;
const GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS: Dword = 0x00000004;
const GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT: Dword = 0x00000002;
const HDT_LOAD_ASSEMBLY_AND_GET_FUNCTION_POINTER: i32 = 5;
const STATUS_UNSUCCESSFUL: Ntstatus = 0xC0000001u32 as Ntstatus;

static INIT: Once = Once::new();
static BOOTSTRAP: Once = Once::new();
static mut REAL_D3D11: Hmodule = ptr::null_mut();

#[link(name = "kernel32")]
unsafe extern "system" {
    fn GetCommandLineW() -> *const u16;
    fn GetModuleHandleExW(dwFlags: Dword, lpModuleName: *const u16, phModule: *mut Hmodule)
    -> Bool;
    fn GetModuleFileNameW(hModule: Hmodule, lpFilename: *mut u16, nSize: Dword) -> Dword;
    fn GetProcAddress(hModule: Hmodule, lpProcName: Lpcstr) -> Farproc;
    fn GetSystemDirectoryW(lpBuffer: *mut u16, uSize: Uint) -> Uint;
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

        let Some(path) = system_d3d11_path() else {
            return;
        };

        REAL_D3D11 = LoadLibraryW(path.as_ptr());
        log_line(&format!(
            "LoadLibraryW real d3d11 => 0x{:x}",
            REAL_D3D11 as usize
        ));
    });
}

unsafe fn system_d3d11_path() -> Option<Vec<u16>> {
    let mut buffer = [0u16; 32768];
    let len = unsafe { GetSystemDirectoryW(buffer.as_mut_ptr(), buffer.len() as Uint) } as usize;
    if len == 0 || len >= buffer.len() {
        return None;
    }

    let mut path = PathBuf::from(std::ffi::OsString::from_wide(&buffer[..len]));
    path.push("d3d11.dll");
    Some(wide_path(&path))
}

unsafe fn get_proc<T>(module: Hmodule, name: &[u8]) -> Option<T> {
    if module.is_null() {
        return None;
    }

    let proc = unsafe { GetProcAddress(module, name.as_ptr() as Lpcstr) };
    if proc.is_null() {
        log_line(&format!(
            "missing export: {}",
            String::from_utf8_lossy(&name[..name.len() - 1])
        ));
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

unsafe fn current_module_dir() -> Option<PathBuf> {
    let mut module = ptr::null_mut();
    let flags =
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
    let address = current_module_dir as *const () as *const u16;

    if unsafe { GetModuleHandleExW(flags, address, &mut module) } == 0 || module.is_null() {
        return None;
    }

    unsafe { module_dir(module) }
}

fn wide_path(path: &Path) -> Vec<u16> {
    path.as_os_str().encode_wide().chain(once(0)).collect()
}

fn wide_str(value: &str) -> Vec<u16> {
    std::ffi::OsStr::new(value)
        .encode_wide()
        .chain(once(0))
        .collect()
}

unsafe fn command_line() -> String {
    unsafe {
        let command_line = GetCommandLineW();
        if command_line.is_null() {
            return String::new();
        }

        let mut len = 0usize;
        while *command_line.add(len) != 0 {
            len += 1;
        }

        String::from_utf16_lossy(std::slice::from_raw_parts(command_line, len))
    }
}

fn parse_command_line(command_line: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut current = String::new();
    let mut backslashes = 0usize;
    let mut in_quotes = false;

    for ch in command_line.chars() {
        match ch {
            '\\' => {
                backslashes += 1;
            }
            '"' => {
                current.extend(std::iter::repeat('\\').take(backslashes / 2));

                if backslashes % 2 == 0 {
                    in_quotes = !in_quotes;
                } else {
                    current.push('"');
                }

                backslashes = 0;
            }
            ' ' | '\t' if !in_quotes => {
                current.extend(std::iter::repeat('\\').take(backslashes));
                backslashes = 0;

                if !current.is_empty() {
                    args.push(std::mem::take(&mut current));
                }
            }
            _ => {
                current.extend(std::iter::repeat('\\').take(backslashes));
                backslashes = 0;
                current.push(ch);
            }
        }
    }

    current.extend(std::iter::repeat('\\').take(backslashes));

    if !current.is_empty() {
        args.push(current);
    }

    args
}

fn command_line_value(args: &[String], names: &[&str]) -> Option<String> {
    for index in 0..args.len().saturating_sub(1) {
        if names
            .iter()
            .any(|name| args[index].eq_ignore_ascii_case(name))
        {
            return Some(args[index + 1].clone());
        }
    }

    None
}

fn doorstop_enabled(args: &[String]) -> bool {
    let Some(value) = command_line_value(
        args,
        &[
            "--doorstop-enable",
            "--doorstop-enabled",
            "--doorstop_enabled",
        ],
    ) else {
        return true;
    };

    !matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "0" | "false" | "no" | "off"
    )
}

unsafe fn bootstrap_bepinex() {
    BOOTSTRAP.call_once(|| unsafe {
        log_line("bootstrap begin");

        let args = parse_command_line(&command_line());
        if !doorstop_enabled(&args) {
            log_line("doorstop disabled by command line");
            return;
        }

        let Some(game_dir) = current_module_dir() else {
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

        let Some(initialize_for_runtime_config) = get_proc::<HostfxrInitializeForRuntimeConfigFn>(
            hostfxr,
            b"hostfxr_initialize_for_runtime_config\0",
        ) else {
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
        log_line(&format!(
            "hostfxr_initialize_for_runtime_config => 0x{:x}",
            rc
        ));

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

        let load_assembly: LoadAssemblyAndGetFunctionPointerFn =
            std::mem::transmute_copy(&load_assembly);
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
        log_line(&format!(
            "load_assembly_and_get_function_pointer => 0x{:x}",
            rc
        ));
        if rc < 0 || entrypoint.is_null() {
            return;
        }

        let entrypoint: ComponentEntryPointFn = std::mem::transmute_copy(&entrypoint);
        let rc = entrypoint(ptr::null_mut(), 0);
        log_line(&format!("NativeEntrypoint.Initialize => 0x{:x}", rc));
    });
}

fn missing_hresult(name: &str) -> Hresult {
    log_line(&format!("missing real d3d11 export: {}", name));
    E_FAIL
}

fn missing_i32(name: &str) -> i32 {
    log_line(&format!("missing real d3d11 export: {}", name));
    -1
}

fn missing_ntstatus(name: &str) -> Ntstatus {
    log_line(&format!("missing real d3d11 export: {}", name));
    STATUS_UNSUCCESSFUL
}

fn missing_dword(name: &str) -> Dword {
    log_line(&format!("missing real d3d11 export: {}", name));
    0
}

fn missing_size_t(name: &str) -> SizeT {
    log_line(&format!("missing real d3d11 export: {}", name));
    0
}

fn missing_void(name: &str) {
    log_line(&format!("missing real d3d11 export: {}", name));
}

macro_rules! forward_d3d11 {
    ($name:ident, $ret:ty, $missing:path, [$($arg:ident: $arg_ty:ty),* $(,)?]) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "system" fn $name($($arg: $arg_ty),*) -> $ret {
            type F = unsafe extern "system" fn($($arg_ty),*) -> $ret;

            unsafe {
                bootstrap_bepinex();
                get_d3d11_fn::<F>(concat!(stringify!($name), "\0").as_bytes()).map_or_else(
                    || $missing(stringify!($name)),
                    |f| f($($arg),*)
                )
            }
        }
    };
}

forward_d3d11!(D3D11CreateDeviceForD3D12, Hresult, missing_hresult, [
    pDevice: *mut c_void,
    Flags: Dword,
    pFeatureLevels: *const Dword,
    FeatureLevels: Dword,
    ppCommandQueues: *const *mut c_void,
    NumQueues: Dword,
    NodeMask: Dword,
    ppDevice: *mut *mut c_void,
    ppImmediateContext: *mut *mut c_void,
    pChosenFeatureLevel: *mut Dword,
]);
forward_d3d11!(D3D11CreateDevice, Hresult, missing_hresult, [
    pAdapter: *mut c_void,
    DriverType: Dword,
    Software: Hmodule,
    Flags: Dword,
    pFeatureLevels: *const Dword,
    FeatureLevels: Dword,
    SDKVersion: Dword,
    ppDevice: *mut *mut c_void,
    pFeatureLevel: *mut Dword,
    ppImmediateContext: *mut *mut c_void,
]);
forward_d3d11!(D3D11CreateDeviceAndSwapChain, Hresult, missing_hresult, [
    pAdapter: *mut c_void,
    DriverType: Dword,
    Software: Hmodule,
    Flags: Dword,
    pFeatureLevels: *const Dword,
    FeatureLevels: Dword,
    SDKVersion: Dword,
    pSwapChainDesc: *const c_void,
    ppSwapChain: *mut *mut c_void,
    ppDevice: *mut *mut c_void,
    pFeatureLevel: *mut Dword,
    ppImmediateContext: *mut *mut c_void,
]);
forward_d3d11!(D3D11On12CreateDevice, Hresult, missing_hresult, [
    pDevice: *mut c_void,
    Flags: Dword,
    pFeatureLevels: *const Dword,
    FeatureLevels: Dword,
    ppCommandQueues: *const *mut c_void,
    NumQueues: Dword,
    NodeMask: Dword,
    ppDevice: *mut *mut c_void,
    ppImmediateContext: *mut *mut c_void,
    pChosenFeatureLevel: *mut Dword,
]);
forward_d3d11!(D3D11CoreCreateDevice, i32, missing_i32, [
    a: RawArg,
    b: RawArg,
    c: RawArg,
    lpModuleName: Lpcstr,
    e: RawArg,
    f: RawArg,
    g: RawArg,
    h: RawArg,
    i: RawArg,
    j: RawArg,
]);
forward_d3d11!(D3D11CoreCreateLayeredDevice, Hresult, missing_hresult, [
    unknown0: *const c_void,
    unknown1: Dword,
    unknown2: *const c_void,
    riid: *const c_void,
    ppvObj: *mut *mut c_void,
]);
forward_d3d11!(D3D11CoreGetLayeredDeviceSize, SizeT, missing_size_t, [
    unknown0: *const c_void,
    unknown1: Dword,
]);
forward_d3d11!(D3D11CoreRegisterLayers, Hresult, missing_hresult, [
    unknown0: *const c_void,
    unknown1: Dword,
]);
forward_d3d11!(CreateDirect3D11DeviceFromDXGIDevice, Hresult, missing_hresult, [
    dxgiDevice: *mut c_void,
    graphicsDevice: *mut *mut c_void,
]);
forward_d3d11!(CreateDirect3D11SurfaceFromDXGISurface, Hresult, missing_hresult, [
    dxgiSurface: *mut c_void,
    graphicsSurface: *mut *mut c_void,
]);
forward_d3d11!(EnableFeatureLevelUpgrade, Hresult, missing_hresult, []);
forward_d3d11!(OpenAdapter10, i32, missing_i32, [adapter: *mut c_void]);
forward_d3d11!(OpenAdapter10_2, i32, missing_i32, [adapter: *mut c_void]);

forward_d3d11!(D3DKMTCloseAdapter, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTCreateAllocation, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTCreateContext, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTCreateDevice, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTCreateSynchronizationObject, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTDestroyAllocation, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTDestroyContext, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTDestroyDevice, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTDestroySynchronizationObject, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTEscape, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetContextSchedulingPriority, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetDeviceState, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetDisplayModeList, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetMultisampleMethodList, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetRuntimeData, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTGetSharedPrimaryHandle, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTLock, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTOpenAdapterFromHdc, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTOpenResource, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTPresent, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTQueryAdapterInfo, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTQueryAllocationResidency, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTQueryResourceInfo, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTRender, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetAllocationPriority, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetContextSchedulingPriority, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetDisplayMode, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetDisplayPrivateDriverFormat, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetGammaRamp, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSetVidPnSourceOwner, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTSignalSynchronizationObject, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTUnlock, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTWaitForSynchronizationObject, Ntstatus, missing_ntstatus, [data: *mut c_void]);
forward_d3d11!(D3DKMTWaitForVerticalBlankEvent, Ntstatus, missing_ntstatus, [data: *mut c_void]);

forward_d3d11!(D3DPerformance_BeginEvent, i32, missing_i32, [
    color: Dword,
    name: *const u16,
]);
forward_d3d11!(D3DPerformance_EndEvent, i32, missing_i32, []);
forward_d3d11!(D3DPerformance_GetStatus, Dword, missing_dword, []);
forward_d3d11!(D3DPerformance_SetMarker, (), missing_void, [
    color: Dword,
    name: *const u16,
]);

#[cfg(test)]
mod tests {
    use super::{doorstop_enabled, parse_command_line};

    #[test]
    fn parses_quoted_doorstop_target() {
        let args = parse_command_line(
            r#""Romestead.exe" --doorstop-enable true --doorstop-target "C:\r2 profile\BepInEx\core\BepInEx.NET.CoreCLR.dll""#,
        );

        assert_eq!(args[0], "Romestead.exe");
        assert_eq!(args[1], "--doorstop-enable");
        assert_eq!(args[2], "true");
        assert_eq!(args[3], "--doorstop-target");
        assert_eq!(
            args[4],
            r#"C:\r2 profile\BepInEx\core\BepInEx.NET.CoreCLR.dll"#
        );
    }

    #[test]
    fn doorstop_is_enabled_by_default() {
        let args = parse_command_line(r#""Romestead.exe""#);

        assert!(doorstop_enabled(&args));
    }

    #[test]
    fn doorstop_can_be_disabled_by_v3_argument() {
        let args = parse_command_line(r#""Romestead.exe" --doorstop-enable false"#);

        assert!(!doorstop_enabled(&args));
    }

    #[test]
    fn doorstop_can_be_disabled_by_v4_argument() {
        let args = parse_command_line(r#""Romestead.exe" --doorstop-enabled 0"#);

        assert!(!doorstop_enabled(&args));
    }
}
