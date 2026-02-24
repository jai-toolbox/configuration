/*
Configuration:

Reads and writes INI-style configuration files with sections, key-value
pairs, and comment support (# and ;).

Make files like this:

settings.ini
------------------------------------
[window]
width = 1280
height = 720
fullscreen = false

[audio]
master_volume = 0.8   ; range 0.0 - 1.0
mute = false
------------------------------------


main.jai (or wherever)
____________________________________
config: Configuration;
config.config_path = "settings.ini";
init(*config);
defer deinit(*config);

// get values from the config file:
title, found := get(*config, "window", "title");
if found  print("Title: %\n", title);

width,  ok_w := get_int(*config, "window", "width");
height, ok_h := get_int(*config, "window", "height");
if ok_w && ok_h  print("Resolution: % x %\n", width, height);

vol, ok_v := get_float(*config, "audio", "master_volume");
if ok_v  print("Volume: %\n", vol);

fs, ok_f := get_bool(*config, "window", "fullscreen");
if ok_f  print("Fullscreen: %\n", fs);

// write values to the config, and then save them.
set(*config, "window", "width", "1920");
set_bool(*config, "window", "fullscreen", true);
save(*config);                          // writes back to settings.ini
save(*config, "settings_backup.ini");   // writes to a different path

// hot-reloading from disk
reload(*config);
____________________________________
*/





#import "Basic";
#import "File";
#import "String";
#import "Hash_Table";

Configuration :: struct {
    config_path: string;
    values: Table(string, Table(string, string));
}

init :: (config: *Configuration) {
    parse_config_file(config);
}

deinit :: (config: *Configuration) {
    free(config.config_path);
    for * inner: config.values {
        deinit(inner);
    }
    deinit(*config.values);
}

reload :: (config: *Configuration) {
    for * inner: config.values {
        deinit(inner);
    }
    table_reset(*config.values);
    parse_config_file(config);
}

parse_config_file :: (config: *Configuration) {
    contents, success := read_entire_file(config.config_path);
    if !success {
        log_error("Unable to open config file: %", config.config_path);
        return;
    }
    defer free(contents);

    // remove carriage returns first (handles windows line endings)
    contents = replace(contents, "\r", "");
    
    current_section: string;
    
    for line: split(contents, "\n") {
        // strip comments
        working := line;
        for i: 0..line.count-1 {
            if line[i] == #char "#" || line[i] == #char ";" {
                working = slice(line, 0, i);
                break;
            }
        }
        
        working = trim(working);
        if working.count == 0 continue;
        
        // Section header
        if working[0] == #char "[" && working[working.count-1] == #char "]" {
            current_section = copy_string(trim(slice(working, 1, working.count - 2)));
            continue;
        }
        
        // key = value
        eq := find_index_from_left(working, "=");
        if eq < 0 continue;
        
        key := copy_string(trim(slice(working, 0, eq)));
        raw_value := slice(working, eq + 1, working.count - eq - 1);
        
        // preserve single space if value is all spaces, otherwise trim
        all_spaces := true;
        for i: 0..raw_value.count-1 {
            if raw_value[i] != #char " " { all_spaces = false; break; }
        }
        value := copy_string(ifx all_spaces && raw_value.count > 0 then " " else trim(raw_value));
        
        // store it
        section_table := table_find_pointer(*config.values, current_section);
        if !section_table {
            section_table = table_add(*config.values, current_section, .{});
        }
        table_set(section_table, key, value);
    }
}

get :: (config: *Configuration, section: string, key: string) -> string, bool {
    inner := table_find_pointer(*config.values, section);
    if !inner return "", false;
    value, found := table_find(inner, key);
    return value, found;
}

get_int :: (config: *Configuration, section: string, key: string) -> int, bool {
    str, found := get(config, section, key);
    if !found return 0, false;
    value, success := string_to_int(str);
    return value, success;
}

get_float :: (config: *Configuration, section: string, key: string) -> float, bool {
    str, found := get(config, section, key);
    if !found return 0, false;
    value, success := string_to_float(str);
    return value, success;
}

get_bool :: (config: *Configuration, section: string, key: string) -> bool, bool {
    value, found := get(config, section, key);
    if !found return false, false;
    if value == "true" return true, true;
    if value == "false" return false, true;
    return false, false;
}

set :: (config: *Configuration, section: string, key: string, value: string) {
    section_table := table_find_pointer(*config.values, section);
    if !section_table {
        section_table = table_add(*config.values, section, .{});
    }
    table_set(section_table, key, value);
}

set_bool :: (config: *Configuration, section: string, key: string, value: bool) {
    set(config, section, key, ifx value then "true" else "false");
}

save :: (config: *Configuration, path: string = "") -> bool {
    actual_path := ifx path.count > 0 then path else config.config_path;
    
    builder: String_Builder;
    
    for config.values {
        section := it_index;
        keys := it;
        
        print_to_builder(*builder, "[%]\n", section);
        
        for keys {
            key := it_index;
            value := it;
            print_to_builder(*builder, "% = %\n", key, value);
        }
        
        print_to_builder(*builder, "\n");
    }
    
    output := builder_to_string(*builder);
    defer free(output);
    
    return write_entire_file(actual_path, output);
}
