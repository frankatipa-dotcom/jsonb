#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <regex>
#include <stdexcept>
#include <iomanip>

std::string readFile(const std::string& path) {
    std::ifstream f(path);
    if (!f) throw std::runtime_error("cannot open: " + path);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

std::string execBash(const std::string& cmd) {
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) throw std::runtime_error("popen failed: " + cmd);

    std::ostringstream ss;
    char buf[256];
    while (fgets(buf, sizeof(buf), pipe))
        ss << buf;

    int rc = pclose(pipe);
    if (rc != 0) throw std::runtime_error("command failed: " + cmd);

    // strip trailing newline
    std::string out = ss.str();
    if (!out.empty() && out.back() == '\n')
        out.pop_back();
    return out;
}

std::string escapeJSON(const std::string& s) {
    std::ostringstream ss;
    for (char c : s) {
        switch (c) {
            case '"':  ss << "\\\""; break;
            case '\\': ss << "\\\\"; break;
            case '\n': ss << "\\n";  break;
            case '\r': ss << "\\r";  break;
            case '\t': ss << "\\t";  break;
            default:
                if (c < 0x20)
                    ss << "\\u" << std::hex << std::setw(4) 
                       << std::setfill('0') << (int)c;
                else
                    ss << c;
        }
    }
    return ss.str();
}

std::string compile(const std::string& tmpl) {
    std::regex re("<#!([\\s\\S]*?)#!>",
                  std::regex::ECMAScript);

    std::string result;
    auto it  = std::sregex_iterator(tmpl.begin(), tmpl.end(), re);
    auto end = std::sregex_iterator();
    size_t pos = 0;



    for (; it != end; ++it) {
        auto& m = *it;

        // everything before the match
        result += tmpl.substr(pos, m.position() - pos);

        std::string cmd = m[1].str();
        std::string out = execBash(cmd);

        // peek at char immediately before <#! in the accumulated result
        bool isString = !result.empty() && result.back() == '"';

        if (isString) {
            result += escapeJSON(out);
        } else {
            result += out;
        }

        pos = m.position() + m.length();
    }
    // remainder
    result += tmpl.substr(pos);
    return result;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: jsonb <template.jsonb>\n";
        return 1;
    }

    try {
        std::string tmpl = readFile(argv[1]);
        std::cout << compile(tmpl);
    } catch (const std::exception& e) {
        std::cerr << "error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}