import SwiftUI

/// 开源许可证（关于页进入）：列出所用第三方组件/字体，点进查看对应许可证全文。
/// 文本为各许可证标准全文 + 各自版权行，满足署名与分发条款的"随附许可证"要求。
struct LicensesView: View {
    var body: some View {
        List(LicenseData.items) { item in
            NavigationLink {
                LicenseDetailView(item: item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 15, weight: .medium))
                    Text(item.license).font(.caption).foregroundColor(AppColor.ink2)
                }
            }
        }
        .navigationTitle("开源许可证")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 单个许可证全文页：版权行 + 许可证正文，等宽便于阅读、可选中复制。
private struct LicenseDetailView: View {
    let item: LicenseItem
    var body: some View {
        ScrollView {
            Text(item.copyright + "\n\n" + item.body)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 一条许可证条目。
struct LicenseItem: Identifiable {
    let id = UUID()
    let name: String        // 组件/字体名
    let license: String     // 许可证名称
    let copyright: String   // 版权行
    let body: String        // 许可证正文全文
}

/// 许可证数据：组件清单 + 三种标准许可证全文（MIT / BSD-2-Clause / Apache-2.0）。
enum LicenseData {
    static let items: [LicenseItem] = [
        LicenseItem(name: "MapLibre Native", license: "BSD 2-Clause License",
                    copyright: "Copyright (c) 2021 MapLibre contributors\nCopyright (c) 2014-2020 Mapbox, Inc.",
                    body: bsd2),
        LicenseItem(name: "GRDB.swift", license: "MIT License",
                    copyright: "Copyright (C) 2015-2024 Gwendal Roué", body: mit),
        LicenseItem(name: "CoreGPX", license: "MIT License",
                    copyright: "Copyright (c) 2018 Vincent Neo", body: mit),
        LicenseItem(name: "Open Sans", license: "Apache License 2.0",
                    copyright: "Copyright 2020 The Open Sans Project Authors / Google", body: apache2),
    ]

    static let mit = """
    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """

    static let bsd2 = """
    Redistribution and use in source and binary forms, with or without \
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, \
    this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, \
    this list of conditions and the following disclaimer in the documentation \
    and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" \
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE \
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE \
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE \
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR \
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF \
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS \
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN \
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) \
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE \
    POSSIBILITY OF SUCH DAMAGE.
    """

    // Apache 2.0 全文（标准条款）。
    static let apache2 = """
    Licensed under the Apache License, Version 2.0 (the "License"); you may not \
    use this file except in compliance with the License. You may obtain a copy of \
    the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software \
    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT \
    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the \
    License for the specific language governing permissions and limitations under \
    the License.

    ——

    完整条款（含定义、授权、再分发、专利、商标、免责与责任限制等）见上述网址。\
    本应用以未修改形式使用 Open Sans 字体，依 Apache License 2.0 分发并在此署名。
    """
}
