import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ Shell Script Runner activated!');

    const disposable = vscode.commands.registerCommand('shrunner.runShellScript', async (resource: vscode.Uri) => {
        if (resource) {
            const scriptPath = resource.fsPath;
            const scriptDir = path.dirname(scriptPath);
            const scriptName = path.basename(scriptPath);

            try {
                // Make script executable first
                await vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: `Making ${scriptName} executable...`,
                    cancellable: false
                }, async () => {
                    try {
                        // Check current permissions
                        const stats = fs.statSync(scriptPath);
                        if (!(stats.mode & 0o111)) { // If not executable
                            fs.chmodSync(scriptPath, '755');
                            vscode.window.showInformationMessage(`✅ Made ${scriptName} executable`);
                        }
                    } catch (chmodError: any) {
                        vscode.window.showErrorMessage(`Failed to make script executable: ${chmodError.message}`);
                        return;
                    }
                });

                // Run the script
                await vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: `Running ${scriptName}...`,
                    cancellable: true
                }, async (progress, token) => {
                    token.onCancellationRequested(() => {
                        vscode.window.showInformationMessage('Script execution cancelled');
                    });

                    // Create terminal
                    const terminal = vscode.window.createTerminal({
                        name: `Run ${scriptName}`,
                        cwd: scriptDir
                    });

                    // Show the terminal
                    terminal.show();

                    // Run the script with chmod +x and execute
                    terminal.sendText(`cd "${scriptDir}" && chmod +x "${scriptName}" && ./"${scriptName}"`);

                    // Wait a bit for output
                    await new Promise(resolve => setTimeout(resolve, 1000));
                });

            } catch (error: any) {
                vscode.window.showErrorMessage(`Failed to run script: ${error.message}`);
                console.error('Script runner error:', error);
            }
        } else {
            vscode.window.showWarningMessage('Please select a shell script file (.sh) to run');
        }
    });

    context.subscriptions.push(disposable);
}

export function deactivate() {}
