<?php
# Why is this written in PHP? I don't know - guess it was easier for me!

define('DS', DIRECTORY_SEPARATOR);

$IDENTIFIERS = ['LOCKFILE', 'ISSTARTEDBYSYSTEM'];
$TARGET_DIRS = [__DIR__ . DS . 'scripts', __DIR__ . DS . 'extras'];
$SOURCE_FILE = __DIR__ . DS . 'common.sh';

######################

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

if (file_exists($SOURCE_FILE))
    $SOURCE_FILE = file_get_contents($SOURCE_FILE);
else
    exit($SOURCE_FILE . ' does not exist');

$SOURCES = [];
foreach ($IDENTIFIERS as $IDENTIFIER) {
    $REGEX = '/#' . $IDENTIFIER . '_START#(.*)#' . $IDENTIFIER . '_END#/s';

    echo 'Fetching: ' . $REGEX . PHP_EOL;
    preg_match($REGEX, $SOURCE_FILE, $matches);

    if (isset($matches[1])) {
        $SOURCES[$IDENTIFIER] = $matches[1];
    }
}

$FILES = [];
foreach ($TARGET_DIRS as $TARGET_DIR) {
    if (!is_dir($TARGET_DIR))
        exit($TARGET_DIR . ' does not exist');

    $SCANDIR = scandir_recursive($TARGET_DIR);

    foreach ($SCANDIR as $FILE) {
        if ($FILE[0] === '.')
            continue;

        $FILES[] = $TARGET_DIR . DS . $FILE;
    }
}

foreach ($FILES as $FILE) {
    echo 'Processing ' . $FILE . '...';

    $FILE_CONTENTS = file_get_contents($FILE);
    $NEW_FILE_CONTENTS = '';

    foreach ($IDENTIFIERS as $IDENTIFIER) {
        if (strpos($FILE_CONTENTS, '#' . $IDENTIFIER . '_START#') == false)
            continue;

        $NEW_FILE_CONTENTS = replace_between($FILE_CONTENTS, '#' . $IDENTIFIER . '_START#', '#' . $IDENTIFIER . '_END#', $SOURCES[$IDENTIFIER]);
    }

    if (strlen($NEW_FILE_CONTENTS) > 0 && $NEW_FILE_CONTENTS != $FILE_CONTENTS) {
        echo ' modified!' . PHP_EOL;
        file_put_contents($FILE, $NEW_FILE_CONTENTS);
    } else {
        echo ' not modified!' . PHP_EOL;
    }
}
