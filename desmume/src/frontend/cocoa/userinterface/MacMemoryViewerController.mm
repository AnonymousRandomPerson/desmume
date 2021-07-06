/*
    Copyright (C) 2021 DeSmuME team
 
    This file is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.
 
    This file is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with the this software.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "MacMemoryViewerController.h"

@implementation MacMemoryViewerController

enum MemRegionType {
    MEMVIEW_ARM9 = 0,
    MEMVIEW_ARM7,
    MEMVIEW_FIRMWARE,
    MEMVIEW_ROM,
    MEMVIEW_FULL
};

struct MemViewRegion
{
    MemRegionType region;
    u32 hardwareAddress; // hardware address of the start of this region
    u32 size; // number of bytes to the end of this region
};

const int ASCII_COLUMN = 17;

const u32 arm9InitAddress = 0x02000000;
const u32 arm7InitAddress = 0x02000000;
static const MemViewRegion s_arm9Region = { MEMVIEW_ARM9, arm9InitAddress, 0x1000000 };
static const MemViewRegion s_arm7Region = { MEMVIEW_ARM7, arm7InitAddress, 0x1000000 };
static const MemViewRegion s_firmwareRegion = { MEMVIEW_FIRMWARE, 0x00000000, 0x40000 };
static const MemViewRegion s_fullRegion = { MEMVIEW_FULL, 0x00000000, 0xFFFFFFF0 };

u32 rowOffset = 0;
NSTimer *updateTimer;

- (NSString *)windowNibName
{
    return @"MemoryViewer";
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [table scrollRowToVisible:0];
    for (NSTableColumn *column in table.tableColumns)
    {
        NSTableHeaderCell *newHeaderCell = [[MonospaceTableHeaderCell alloc] init];
        newHeaderCell.stringValue = column.headerCell.stringValue;
        newHeaderCell.alignment = column.headerCell.alignment;
        column.headerCell = newHeaderCell;
    }
    rowOffset = s_arm9Region.hardwareAddress / 0x10;
}

- (void)updateTable
{
    // Calling reloadData on the whole table is very slow, so update individual memory cells manually if they change.
    NSRange visibleRange = [table rowsInRect:[table visibleRect]];
    for (int i = 0; i < visibleRange.length; i++)
    {
        int row = visibleRange.location + i;
        
        // Skip the address column since that doesn't change.
        for (int column = 1; column <= ASCII_COLUMN; column++)
        {
            NSTableCellView *tableRow = [table viewAtColumn:column row:row makeIfNecessary:true];
            if (tableRow.textField.currentEditor == tableRow.textField.window.firstResponder)
            {
                // If the cell is being edited, don't refresh the value.
                continue;
            }
            
            NSString *cellValue;
            if (column == ASCII_COLUMN)
            {
                cellValue = [self getAsciiDisplayString:row];
            }
            else
            {
                cellValue = [self getMemoryDisplayString:row column:column - 1];
            }
            
            if (![cellValue isEqualToString:tableRow.textField.stringValue])
            {
                tableRow.textField.stringValue = cellValue;
                [table setNeedsDisplayInRect:[table frameOfCellAtColumn:column row:row]];
            }
        }
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if (updateTimer == nil)
    {
        updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                       target:self
                                                     selector:@selector(updateTable)
                                                     userInfo:nil
                                                      repeats:true];
    }
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (updateTimer != nil)
    {
        [updateTimer invalidate];
        updateTimer = nil;
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return s_arm9Region.size / 0x10;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    NSString *cellValue;
    if ([@"Address" isEqualToString:tableColumn.identifier])
    {
        int displayRow = rowOffset + row;
        char cellCString[9];
        sprintf(cellCString, "%07X0", displayRow);
        cellValue = [NSString stringWithCString:cellCString encoding:NSASCIIStringEncoding];
    }
    else if ([@"ASCII" isEqualToString:tableColumn.identifier])
    {
        cellValue = [self getAsciiDisplayString:row];
    }
    else
    {
        cellValue = [self getMemoryDisplayString:row column:tableColumn.identifier.intValue];
    }
    
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    cellView.textField.stringValue = cellValue;
    return cellView;
}

- (NSString *)getAsciiDisplayString:(int)row
{
    u8 values[17];
    u32 address = s_arm9Region.hardwareAddress + row * 16;
    MMU_DumpMemBlock(ARMCPU_ARM9, address, 16, (u8*) &values);
    // Null-terminate to make a valid C-string.
    values[16] = '\0';
    for (int i = 0; i < 16; i++)
    {
        if (values[i] < 0x20 || values[i] >= 0x7F)
        {
            values[i] = '.';
        }
    }
    return [NSString stringWithCString:(char*)values encoding:NSASCIIStringEncoding];
}

- (NSString *)getMemoryDisplayString:(int)row
                              column:(int)column
{
    u8 value;
    u32 address = s_arm9Region.hardwareAddress + row * 16 + column;
    MMU_DumpMemBlock(ARMCPU_ARM9, address, 1, &value);
    char cellCString[3];
    sprintf(cellCString, "%02X", value);
    return [NSString stringWithCString:cellCString encoding:NSASCIIStringEncoding];
}

- (IBAction)editMemory:(NSTextField *)sender {
    u32 address = s_arm9Region.hardwareAddress + table.selectedRow * 16 + [sender.identifier integerValue];
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:sender.stringValue];
    [scanner scanHexInt:&value];
    MMU_write8(ARMCPU_ARM9, address, value);
}

@end

// Makes the table header use a monospace font.
@implementation MonospaceTableHeaderCell

- (NSFont *)font
{
    return [NSFont fontWithName:@"Monaco" size:13];
}

@end
