<?php
# Why is this written in PHP? I don't know - guess it was easier for me!

define('DS', DIRECTORY_SEPARATOR);

$markers = ['LOCKFILE', 'ISSTARTEDBYSYSTEM', 'ISMERLINFIRMWARE'];
$target_dirs = [__DIR__ . DS . 'scripts', __DIR__ . DS . 'extras'];
$source_file = __DIR__ . DS . 'common.sh';

#########################

// https://stackoverflow.com/a/46697247
function scandir_recursive($dir) {
    $result = [];
    foreach(scandir($dir) as $filename) {
        if ($filename[0] === '.')
        continue;

        $filePath = $dir . DS  . $filename;
        if (is_dir($filePath)) {
            foreach (scandir_recursive($filePath) as $childFilename) {
                $result[] = $filename . DS  . $childFilename;
            }
        } else {
            $result[] = $filename;
        }
    }
    return $result;
}

// https://stackoverflow.com/a/6875997
function replace_between($str, $needle_start, $needle_end, $replacement) {
    $pos = strpos($str, $needle_start);
    $start = $pos === false ? 0 : $pos + strlen($needle_start);
    $pos = strpos($str, $needle_end, $start);
    $end = $pos === false ? strlen($str) : $pos;
    return substr_replace($str, $replacement, $start, $end - $start);
}

if (file_exists($source_file))
    $source_file = file_get_contents($source_file);
else
    exit($source_file . ' does not exist');

$sources = [];
foreach ($markers as $marker) {
    $regex = '/#' . $marker . '_START#(.*)#' . $marker . '_END#/s';

    echo 'Fetching: ' . $regex . PHP_EOL;
    preg_match($regex, $source_file, $matches);

    if (isset($matches[1])) {
        $sources[$marker] = $matches[1];
    }
}

$files = [];
foreach ($target_dirs as $target_dir) {
    if (!is_dir($target_dir))
        exit($target_dir . ' does not exist');

    $scandir = scandir_recursive($target_dir);

    foreach ($scandir as $file) {
        if ($file[0] === '.')
            continue;

        $files[] = $target_dir . DS . $file;
    }
}

foreach ($files as $file) {
    echo 'Processing ' . $file . '...';

    $contents = file_get_contents($file);
    $new_contents = $contents;

    foreach ($markers as $marker) {
        if (strpos($contents, '#' . $marker . '_START#') == false)
            continue;

        $new_contents = replace_between($new_contents, '#' . $marker . '_START#', '#' . $marker . '_END#', $sources[$marker]);
    }

    if ($new_contents != $contents) {
        echo ' modified!' . PHP_EOL;
        file_put_contents($file, $new_contents);
    } else {
        echo ' not modified!' . PHP_EOL;
    }
}
